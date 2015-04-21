#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'benchmark'
  require 'mysql2'
  require 'singleton'
  require_relative 'communicator'
  require_relative 'logger'
  require_relative 'manager'
  require_relative 'memorizer'
  require_relative 'scaler'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Monitor

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
      @monitoring_cluster_availability = false
      @monitoring_cluster_latency = false
      @monitoring_cluster_capacity = false
      @monitoring_cluster_scalability = false
      @mysql_client = nil
    end
    
    #--------------------------------------------------------------------------
    # Main method
    #--------------------------------------------------------------------------

    def monitor_cluster      
      timeout = 1 # second

      # Monitor the availability of the cluster
      Thread.new do
        loop do
          if is_cluster_configured?
            monitor_cluster_availability
          end

          sleep(timeout)
        end
      end

      # Monitor the latency of the cluster
      Thread.new do
        loop do
          if is_cluster_online?
            monitor_cluster_latency
          end

          sleep(timeout)
        end
      end

      # Monitor the used capacity of the cluster
      Thread.new do
        loop do
          if is_cluster_online? || is_cluster_importing?
            monitor_used_cluster_capacity
          end

          sleep(timeout)
        end
      end
    end
    
    #--------------------------------------------------------------------------
    # Monitor: Availability
    #--------------------------------------------------------------------------

    def monitor_cluster_availability
      if !@monitoring_cluster_availability
        $logger.log_action('Monitoring Cluster Availability', 'monitor')
        @monitoring_cluster_availability = true
      end

      # Get all the nodes which have to be online
      active_cluster_nodes = $manager.get_active_cluster_nodes
      load_balancer_node = $manager.get_cluster_load_balancer_node

      # Remove load balancer node (not listed in the ndb_mgm process)
      nodes = active_cluster_nodes - [load_balancer_node]

      # Declare some variables which will be used in the loop below
      host = nodes.first['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']
      allowed_node_states = ['started', 'connected']
      attempts = 0
      max_attempts = 15
      some_node_is_offline = false

      # Check each node status via the ndb_mgm process (SSH)
      loop do
        # Reset loop variables
        output = []
        new_output = []
        attempts += 1
        some_node_is_offline = false

        # Retrieve each node status separately
        nodes.each do |node|
          $communicator.query_ssh(host, user, password) do |ssh|
            data = ssh.exec!("ndb_mgm -e '#{node['nodeid']} STATUS'")
            output << [node['nodeid'], data]
          end
        end
        
        if output.empty?
          some_node_is_offline = true
        else
        # Check if at least one node is offline
          output.each do |item|
            if item[1] != "\n"
              # Extract the current node status from SSH output
              # Example: "Connected to Management Server at:
              #  localhost:1186\nNode 3: started (mysql-5.6.21 ndb-7.3.7)\n"

              node_status = item[1].gsub(/[\n]/, ' ').split(' ')[8]
              new_output << [item[0], node_status]

              unless allowed_node_states.include?(node_status)
                some_node_is_offline = true
              end 
            end
          end
        end

        sleep(2) # seconds

        break unless (some_node_is_offline && attempts < max_attempts)
      end

      # Decide wheter the cluster is online or not
      if !(some_node_is_offline && attempts < max_attempts)
        
        # Check current cluster status again before saving the new status
        allowed_states = ['online', 'configuring', 'importing']
        allowed_states.concat ['scaling_up', 'scaling_down']

        unless allowed_states.include?($memorizer.cluster_status)
          # Update cluster status
          $memorizer.cluster_status = 'online'
          $logger.log_state('Cluster is online', 'cluster')
        end
        
        true

      else
        # The cluster is in an error state
        $memorizer.cluster_status = 'error'
        @monitoring_cluster_availability = false
        
        $logger.log_state('Cluster is not online', 'cluster')
        $logger.log_error('Not all nodes are operational.', 'monitor')
        $logger.log_info("Please check the 'ndb_mgm' process.", 'monitor')
        
        false
      end

    rescue => error
      $logger.log_error("#{error}.", 'monitor')
    end

    #--------------------------------------------------------------------------
    # Monitor: Latency
    #--------------------------------------------------------------------------

    def monitor_cluster_latency
      if !@monitoring_cluster_latency
        $logger.log_action('Monitoring Cluster Latency', 'monitor')
        @monitoring_cluster_latency = true
      end

      client = nil
      attempts = 0
      max_attempts = 30
      host = $manager.identify_mysql_host
      client_not_created = true

      # Try to create a MySQL client
      loop do
        attempts += 1
        
        client = $communicator.create_new_mysql_client(host)

        if client.nil?
          message = "MySQL client can't be created yet (#{host})."
          $logger.log_error(message, 'monitor')
        else
          client_not_created = false
        end
        
        sleep(1) # second
        
        break unless (client_not_created && attempts < max_attempts)
      end

      # Run a small benchmark query
      if !(client_not_created && attempts < max_attempts)
        query_time = Benchmark.realtime do
          client.query(CONFIG['monitor']['query'])
          client.close
        end
        
        query_time *= 1000 # transform seconds into milliseconds
        
        # Check status again to be sure
        if is_cluster_online?
          # Save the current latency
          $memorizer.cluster_latency = "#{query_time}ms"
          $scaler.save_cluster_latency(query_time)
          $scaler.save_average_cluster_latencies

          # Check if the cluster has to be scaled
          $scaler.scale_cluster?($scaler.scale_cluster_trigged_by_latency?)
        else
          $memorizer.reset('cluster_latency')
        end
        
      else
        $memorizer.cluster_status = 'error'
        $memorizer.reset('cluster_latency')
        
        @monitoring_cluster_latency = false

        $logger.log_state('Cluster is not online', 'cluster')
        $logger.log_error('MySQL server is not reachable.', 'monitor')
        $logger.log_info('Try to restart the entire Cluster.', 'monitor')
      end

    rescue => error
      $logger.log_error("#{error}.", 'monitor')
    end

    #--------------------------------------------------------------------------
    # Monitor: Capacity
    #--------------------------------------------------------------------------

    def monitor_used_cluster_capacity
      if !@monitoring_cluster_capacity
        $logger.log_action('Monitoring Cluster Capacity', 'monitor')
        @monitoring_cluster_capacity = true
      end

      # Get all active cluster data nodes
      active_data_nodes = $manager.get_active_cluster_data_nodes
      host = $manager.get_cluster_management_node['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']
      output = []
      new_output = []

      # Retrieve the memory usage of every active data node via ndb_mgm (SSH) 
      active_data_nodes.each do |node|
        $communicator.query_ssh(host, user, password) do |ssh|
          data = ssh.exec!("ndb_mgm -e '#{node['nodeid']} REPORT MEMORYUSAGE'")
          output << [node['nodeid'], data]
        end
      end

      # Clean output
      output.each_with_index do |item, index|
        # Extract the used capacity
        item[1] = item[1].gsub(/[(]/, ' ').split(' ')[11]
        new_output << item
      end

      # Calculate the used cluster capacity
      capacity_used = 0
      capacity_per_data_node = CONFIG['settings']['data']['data_memory_size']
      capacity_per_data_node = capacity_per_data_node.delete('M').to_i

      # Transform retrieved percentage values in megabytes
      new_output.each do |item|
        percentage = item[1].delete('%').to_f / 100
        capacity_used += percentage * capacity_per_data_node
      end

      node_count_per_nodegroup = $manager.get_node_count_per_nodegroup

      capacity_used /= node_count_per_nodegroup

      # Check cluster status again to be sure
      if is_cluster_online? || is_cluster_importing?
        
        # Correct dirty SSH read errors
        if capacity_used > $manager.get_cluster_capacity.delete('MB').to_f
          capacity_used = -1
        end

        # Save the current cluster capacity
        $memorizer.cluster_used_capacity = "#{capacity_used}MB"

        # Check if the cluster has to be scaled
        $scaler.scale_cluster?($scaler.scale_cluster_trigged_by_capacity?)
      end

    rescue => error
      $logger.log_error("#{error}.", 'monitor')
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------

    def is_cluster_configured?
      $manager.get_cluster_management_node != nil
    end

    #---

    def is_cluster_online?
      $memorizer.cluster_status == 'online'
    end

    #---

    def is_cluster_importing?
      $memorizer.cluster_status == 'importing'
    end

    #---

  end
end

#------------------------------------------------------------------------------

$monitor = ADAPT::Monitor.instance