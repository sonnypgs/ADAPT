#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'singleton'
  require_relative 'communicator'
  require_relative 'configurator'
  require_relative 'logger'
  require_relative 'manager'
  require_relative 'memorizer'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Scaler

    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------

    include Singleton

    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------

    CONFIG = $utils.get_config

    #--------------------------------------------------------------------------
    # Instance variables
    #--------------------------------------------------------------------------

    def initialize
      @cluster_latencies = []
    end

    #--------------------------------------------------------------------------
    # Check methods
    #--------------------------------------------------------------------------

    def scale_cluster?(direction)
      allowed_states = ['online']
      return unless allowed_states.include?($memorizer.cluster_status)

      case direction
      when 'up'
        scale_cluster_up
      when 'down'
        scale_cluster_down
      else
        # do nothing here
      end
    end

    #---

    def scale_cluster_trigged_by_capacity?
      used_capacity = $memorizer.cluster_used_capacity.delete('MB').to_f
      scale_up_capacity = calculate_scale_up_capacity
      scale_down_capacity = caculate_scale_down_capacity

      if used_capacity >= scale_up_capacity
        message = 'Cluster will be scaled up (triggered by capacity).'
        $logger.log(message, 'scaler')
        'up'
      elsif used_capacity <= scale_down_capacity
        message = 'Cluster will be scaled down (triggered by capacity).'
        $logger.log(message, 'scaler')
        'down'
      else
        'none'
      end
    end

    #---

    def scale_cluster_trigged_by_latency?
      fast_average_latency = $memorizer.cluster_fast_average_latency
      fast_average_latency = fast_average_latency.delete('ms').to_f
      slow_average_latency = $memorizer.cluster_slow_average_latency
      slow_average_latency = slow_average_latency.delete('ms').to_f

      trigger_factor = CONFIG['scaling']['latency_trigger_factor']

      if fast_average_latency > (slow_average_latency * trigger_factor)
        message = 'Cluster will be scaled up (triggered by latency).'
        $logger.log(message, 'scaler')
        'up'
      elsif slow_average_latency > (fast_average_latency * trigger_factor)
        message = 'Cluster will be scaled down (triggered by latency).'
        $logger.log(message, 'scaler')
        'down'
      else
        'none'
      end
    end

    #--------------------------------------------------------------------------
    # Scale: UP
    #--------------------------------------------------------------------------

    def scale_cluster_up
      $memorizer.scale_up_attempts ||= 0 # assign if not already done
      $memorizer.scale_up_attempts += 1
      max_scale_up_attempts = CONFIG['scaling']['max_scale_up_attempts']
      return if $memorizer.scale_up_attempts > max_scale_up_attempts

      sleep(2) # seconds

      $memorizer.cluster_status = 'scaling_up'
      $logger.log_state('Cluster is scaling up', 'cluster')
      $logger.log_action('Scaling Cluster UP', 'scaler')
      $logger.log("Attempt: #{$memorizer.scale_up_attempts}", 'scaler')

      # Check if there are enough inactive nodes available
      inactive_nodes = $manager.get_inactive_cluster_data_nodes
      needed_nodes_to_scale_up = get_needed_node_count_to_scale_up

      if inactive_nodes.count < needed_nodes_to_scale_up
        error = 'Not enough nodes are available for the scaling process.'
        $logger.log_error(error, 'scaler')
        $memorizer.cluster_status = 'online'
        $logger.log_state('Cluster is online', 'cluster')
        return # exit method
      end

      # Start inactive nodes (via the CloudStack API and SSH)
      user = CONFIG['credentials']['data']['ssh']['user']
      password = CONFIG['credentials']['data']['ssh']['password']
      configured_nodes = $configurator.get_cluster_nodes_config
      highest_existing_node_group = $manager.find_highest_existing_node_group
      new_node_group = (highest_existing_node_group.to_i + 1).to_s
      activated_node_ids = []

      inactive_nodes.first(needed_nodes_to_scale_up).each do |node|
        activated_node_ids << node['nodeid']
        host = node['ip']

        $logger.log("Starting inactive node (#{node['ip']}).", 'scaler')
        $manager.start_vm(node['id'])
        no_ssh_connection = true
        attempts = 0
        max_attempts = 30

        loop do
          attempts += 1
          $communicator.query_ssh(host, user, password) do |ssh|
            ssh.exec!('ndbd --initial')
            no_ssh_connection = false
          end
          
          sleep(2) # seconds

          break unless (no_ssh_connection && attempts < max_attempts)
        end

        # Change nodegroup configuration
        configured_nodes['data'][node['nodeid']]['nodegroup'] = new_node_group
      end

      # Wait until activated nodes are not starting anymore
      host = $manager.get_cluster_management_node['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']
      nodes_are_starting = false
      attempts = 0
      max_attempts = 30
      
      loop do
        attempts += 1
        output = []
        
        activated_node_ids.each do |nodeid|
          $communicator.query_ssh(host, user, password) do |ssh|
            out = ssh.exec!("ndb_mgm -e '#{nodeid} STATUS'")
            output << out.gsub(/[\n]/, ' ').split(' ')[8]
          end

          $logger.log("Waiting for starting node (id: #{nodeid}).", 'scaler')
        end

        output.each do |item|
          nodes_are_starting = true if item != 'started'
        end

        sleep(2) # seconds
        
        break unless (nodes_are_starting && attempts < max_attempts)
      end

      # Update cluster_nodes.yaml
      $logger.log('Updating cluster_nodes.yaml', 'scaler')
      $configurator.write_cluster_nodes_config(configured_nodes.to_yaml)

      # Create new node group (via SSH)
      $logger.log('Creating new node group.', 'scaler')
      activated_node_ids = activated_node_ids.join(',')

      $communicator.query_ssh(host, user, password) do |ssh|
        ssh.exec!("ndb_mgm -e 'CREATE NODEGROUP #{activated_node_ids}'")
      end

      # Reorganize and optimize all distributed tables (via MySQL)
      host = $manager.identify_mysql_host
      client = $communicator.create_new_mysql_client(host)
      db_name = CONFIG['simulator']['database']['name']
      
      tables = []
      results = client.query("SHOW TABLES FROM #{db_name}")
      
      results.each do |result|
        tables << result.to_a[0][1]
      end

      tables.each do |table|
        $logger.log("Distribute table '#{db_name}.#{table}'.", 'scaler')
        command = "ALTER TABLE #{db_name}.#{table} REORGANIZE PARTITION"
        client.query(command)

        $logger.log("Optimize table '#{db_name}.#{table}'.", 'scaler')
        client.query("OPTIMIZE TABLE #{db_name}.#{table}")
      end

      client.close

      $memorizer.reset('scale_up_attempts')
      $memorizer.reset('scale_down_attempts')
      @cluster_latencies = [] # reset values

      # Update cluster status
      $memorizer.cluster_status = 'online'
      $logger.log_state('Cluster is online', 'cluster')

    rescue => error
      $logger.log_error("#{error}.", 'scaler')
      $memorizer.cluster_status = 'online'
      $logger.log_state('Cluster is online', 'cluster')
    end
    
    #--------------------------------------------------------------------------
    # Scale: DOWN
    #--------------------------------------------------------------------------
    
    def scale_cluster_down
      $memorizer.scale_down_attempts ||= 0 # assign if not already done
      $memorizer.scale_down_attempts += 1
      max_scale_down_attempts = CONFIG['scaling']['max_scale_down_attempts']
      return if $memorizer.scale_down_attempts > max_scale_down_attempts

      sleep(2) # seconds

      $memorizer.cluster_status = 'scaling_down'
      $logger.log_state('Cluster is scaling down', 'cluster')
      $logger.log_action('Scaling Cluster DOWN', 'scaler')
      $logger.log("Attempt: #{$memorizer.scale_down_attempts}", 'scaler')

      # Coalesce partitioned tables (via MySQL)
      host = $manager.identify_mysql_host
      client = $communicator.create_new_mysql_client(host)
      db_name = CONFIG['simulator']['database']['name']
      number_of_partitions_to_remove = 1

      tables = []
      results = client.query("SHOW TABLES FROM #{db_name}")
      
      results.each do |result|
        tables << result.to_a[0][1]
      end
      
      tables.each do |table|
        message = "Coalescing distributed table '#{db_name}.#{table}'."
        $logger.log(message, 'scaler')

        command = "ALTER TABLE #{db_name}.#{table}"
        command << " COALESCE PARTITION #{number_of_partitions_to_remove}"
        client.query(command)  
      end

      client.close

      # Drop the latest nodegroup via ndb_mgm (SSH)
      highest_existing_node_group = $manager.find_highest_existing_node_group
      message = "Dropping node group (#{highest_existing_node_group})."
      $logger.log(message, 'scaler')
      
      host = $manager.get_cluster_management_node['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']

      $communicator.query_ssh(host, user, password) do |ssh|
        ssh.exec!("ndb_mgm -e 'DROP NODEGROUP #{highest_existing_node_group}'")
      end

      # Identify cluster nodes which will be deactivated and shut down
      configured_nodes = $configurator.get_cluster_nodes_config
      nodes_to_deactivate = []
      active_cluster_data_nodes = $manager.get_active_cluster_data_nodes

      active_cluster_data_nodes.each do |node|
        if node['nodegroup'] == highest_existing_node_group
          nodes_to_deactivate << node
        end
      end

      # Deactive and shutdown unneeded cluster nodes
      nodes_to_deactivate.each do |node|
        nodeid = node['nodeid']
        $logger.log("Stopping node (#{node['ip']}).", 'scaler')
        # Normally each node has to be additionally stopped via the ndb_mgm 
        #  process, unfortunately this takes much too long (so skip this step)

        # Set node inactive
        configured_nodes['data'][nodeid]['nodegroup'] = 65536
        
        # Shutdown node (via CloudStack API)
        $logger.log("Shutting down node (#{node['ip']}).", 'scaler')
        $manager.stop_vm(node['id'])
      end

      # Update cluster_nodes.yaml
      $logger.log('Updating cluster_nodes.yaml.', 'scaler')
      $configurator.write_cluster_nodes_config(configured_nodes.to_yaml)

      $memorizer.reset('scale_up_attempts')
      $memorizer.reset('scale_down_attempts')
      @cluster_latencies = [] # reset

      # Update cluster status
      $memorizer.cluster_status = 'online'
      $logger.log_state('Cluster is online', 'cluster')

    rescue => error
      $logger.log_error("#{error}.", 'scaler')
      $memorizer.cluster_status = 'online'
      $logger.log_state('Cluster is online', 'cluster')
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------

    def save_cluster_latency(latency)
      # Save max. 600 cluster latency values
      if @cluster_latencies.count >= 600
        # Delete first element
        @cluster_latencies.shift(1)
      end

      # Add new value
      @cluster_latencies << latency
    end

    #---

    def save_average_cluster_latencies
      latest_values = CONFIG['scaling']['fast_average_value_count']
      fast_average_latency = calculate_average_cluster_latency(latest_values)
      $memorizer.cluster_fast_average_latency = fast_average_latency

      latest_values = CONFIG['scaling']['slow_average_value_count']
      slow_average_latency = calculate_average_cluster_latency(latest_values)
      $memorizer.cluster_slow_average_latency = slow_average_latency
    end

    #---

    def calculate_average_cluster_latency(latest_values)
      latencies = @cluster_latencies.clone
      
      to_drop = latencies.count - latest_values
      to_drop = 0 if to_drop < 0
      latencies.shift(to_drop)

      average_latency = latencies.reduce(:+) / latencies.count 
      
      "#{average_latency}ms"

    rescue
      '-1ms'
    end

    #---

    def calculate_scale_up_capacity
      factor = CONFIG['scaling']['scale_up_capacity_trigger']
      $manager.get_cluster_capacity.delete('MB').to_f * factor
    end

    #---

    def caculate_scale_down_capacity
      cluster_capacity = $manager.get_cluster_capacity.delete('MB').to_f
      capacity_per_node = CONFIG['settings']['data']['data_memory_size']
      capacity_per_node = capacity_per_node.delete('M').to_f
      factor = CONFIG['scaling']['scale_down_capacity_trigger']

      cluster_capacity - (capacity_per_node * factor)
    end

    #---

    def get_needed_node_count_to_scale_up
      $manager.get_node_count_per_nodegroup
      # TODO: calculate how many nodes are exactly needed 
      #  (node_count_per_nodegroup * factor)
    end

    #---

  end
end

#------------------------------------------------------------------------------

$scaler = ADAPT::Scaler.instance