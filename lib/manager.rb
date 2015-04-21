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
  require_relative 'memorizer'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Manager

    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------

    include Singleton

    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------

    CONFIG = $utils.get_config

    #--------------------------------------------------------------------------
    # Virtual Machine (VM) methods
    #--------------------------------------------------------------------------

    def get_all_vms
      cloudstack = $communicator.connect_to_cloudstack
      vms = cloudstack.list_virtual_machines['virtualmachine']

      # Modify virtual machines
      vms.map! do |vm|
        {
          'id'          => vm['id'],
          'displayname' => vm['displayname'],
          'name'        => vm['name'],
          'ip'          => vm['nic'][0]['ipaddress'],
          'state'       => vm['state']
        }
      end
    end

    #---

    def get_cluster_vms
      get_all_vms - get_non_cluster_vms
    end

    #---

    def get_non_cluster_vms
      vms = get_all_vms
      nodes = get_cluster_nodes

      nodes.each do |node|
        vms.delete_if do |vm|
          if !vm.nil? && !node.nil?
            vm['id'] == node['id']
          else
            false
          end
        end
      end

      vms
    end

    #---

    def get_online_cluster_vms
      # online: VM running + SSH-reachable
      vms = get_cluster_vms
      allowed_vm_states = ['Running']
      online_vms = []

      vms.each do |vm|
        if allowed_vm_states.include?(vm['state'])
          if is_node_online?(vm['id'])
            online_vms << vm
          end
        end
      end

      online_vms
    end

    #---

    def get_offline_cluster_vms
      # offline: VM running + non-SSH-reachable
      get_cluster_vms - get_online_cluster_vms - get_stopped_cluster_vms
    end

    #---

    def get_stopped_cluster_vms
      # stopped: VM not running + non-SSH-reachable (implicit)
      vms = get_cluster_vms
      allowed_vm_states = ['Stopped', 'Shutdowned']

      vms.delete_if do |vm|
        !allowed_vm_states.include?(vm['state'])
      end
    end

    #---

    def get_vm(vm_id)
      cloudstack = $communicator.connect_to_cloudstack

      vm = cloudstack.list_virtual_machines({
        :id => vm_id
      })['virtualmachine'].first
    end

    #---

    def start_vm(vm_id)
      result = { :job_id => nil, :error => nil }

      vm = get_vm(vm_id)
      allowed_vm_states = ['Stopped', 'Shutdowned']

      if allowed_vm_states.include?(vm['state'])
        cloudstack = $communicator.connect_to_cloudstack

        $logger.log("Starting VM (#{vm['displayname']}).", 'cluster')
        
        result[:job_id] = cloudstack.start_virtual_machine({
          :id => vm_id
        })['jobid']

      else
        result[:error] = vm['state']
      end

      result
    end

    #---

    def stop_vm(vm_id)
      result = { :job_id => nil, :error => nil }
      vm = get_vm(vm_id)
      allowed_vm_states = ['Running']

      if allowed_vm_states.include?(vm['state'])
        cloudstack = $communicator.connect_to_cloudstack
        
        $logger.log("Stopping VM (#{vm['displayname']}).", 'cluster')

        result[:job_id] = cloudstack.stop_virtual_machine({
          :id => vm_id
        })['jobid']
        
      else
        result[:error] = vm['state']
      end

      result
    end

    #---

    def reboot_vm(vm_id)
      # Can be rebooted in online and offline state
      result = { :job_id => nil, :error => nil }
      
      vm = get_vm(vm_id)
      allowed_vm_states = ['Running']
      start_vm_states = ['Stopped', 'Shutdowned']

      if allowed_vm_states.include?(vm['state'])
        cloudstack = $communicator.connect_to_cloudstack
        
        $logger.log("Rebooting VM (#{vm['displayname']}).", 'cluster')

        result[:job_id] = cloudstack.reboot_virtual_machine({
          :id => vm_id
        })['jobid']
        
      elsif start_vm_states.include?(vm['state'])
        result[:job_id] = start_vm(vm_id)[:job_id]
      
      else
        result[:error] = vm['state']
      end

      result
    end

    #--------------------------------------------------------------------------
    # Node methods
    #--------------------------------------------------------------------------

    def get_cluster_nodes
      nodes = []
      nodes.push    get_cluster_management_node
      nodes.concat  get_cluster_sql_nodes
      nodes.concat  get_cluster_data_nodes
      nodes.push    get_cluster_load_balancer_node
      nodes.reject  &:nil?
    end

    #---

    def get_active_cluster_nodes
      nodes = []
      nodes.push    get_cluster_management_node
      nodes.concat  get_cluster_sql_nodes
      nodes.concat  get_active_cluster_data_nodes
      nodes.push    get_cluster_load_balancer_node
      nodes.reject  &:nil?
    end

    #---

    def get_cluster_management_node
      config = $configurator.get_cluster_nodes_config
      node = config['management'].first[1]
      node['nodeid'] = config['management'].first[0]
      
      node

    rescue
      nil
    end

    #---

    def get_cluster_sql_nodes
      config = $configurator.get_cluster_nodes_config
      nodes = config['sql']

      if !nodes.nil?
        nodes.map do |node|
          current_node = node
          node = current_node[1]
          node['nodeid'] = current_node[0]
          node
        end
      else
        []
      end

    rescue
      []
    end

    #---

    def get_cluster_data_nodes
      config = $configurator.get_cluster_nodes_config
      nodes = config['data']

      if !nodes.nil?
        nodes.map do |node|
          current_node = node
          node = current_node[1]
          node['nodeid'] = current_node[0]
          node
        end
      else
        []
      end

    rescue
      []
    end

    #---

    def get_active_cluster_data_nodes
      get_cluster_data_nodes.keep_if do |node|
        node['nodegroup'].to_i != 65536
      end
    end

    #---

    def get_inactive_cluster_data_nodes
      get_cluster_data_nodes.keep_if do |node|
        node['nodegroup'].to_i == 65536
      end
    end

    #---

    def get_cluster_load_balancer_node
      config = $configurator.get_cluster_nodes_config
      
      node = config['loadbalancer'].first[1]
      node['nodeid'] = config['loadbalancer'].first[0]
      
      node

    rescue
      nil
    end

    #---

    def ensure_that_cluster_nodes_are_online
      $logger.log_action('Ensuring that Cluster Nodes are online', 'cluster')
      
      start_stopped_nodes
      restart_offline_nodes
      wait_until_cluster_nodes_are_online
    end

    #---

    def wait_until_cluster_nodes_are_online
      $logger.log_action('Waiting until Cluster Nodes are online', 'cluster')
      
      # Constantly checking the SSH-connectability
      nodes = get_cluster_nodes
      node_count = nodes.length
      attempts = 0
      max_attempts = 10
      online_count = 0

      loop do
        attempts += 1

        nodes.delete_if do |node|
          if is_node_online?(node['id'])
            online_count += 1
            true
          else
            false
          end
        end

        $logger.log('Still checking and waiting.', 'cluster')
        
        sleep(5) # seconds

        break unless (online_count != node_count) && (attempts < max_attempts)
      end

      sleep(5) # seconds
    end

    #---

    def start_stopped_nodes
      # stopped: VM is stopped, implicitly no SSH connection
      vms = get_stopped_cluster_vms
      vms.each do |vm|
        start_vm(vm['id'])
      end
    end

    #---

    def restart_offline_nodes
      # offline: VM is running, but no SSH connection
      vms = get_offline_cluster_vms
      vms.each do |vm|
        reboot_vm(vm['id'])
      end
    end

    #--------------------------------------------------------------------------
    # Service methods
    #--------------------------------------------------------------------------
    
    def start_node_services
      $logger.log_action('Starting Node Services', 'cluster')
      
      # Start all node services
      start_management_nodes_service
      start_sql_nodes_service
      start_data_nodes_service
      start_load_balancer_nodes_service
    end

    #---

    def stop_node_services
      $logger.log_action('Stopping Node Services', 'cluster')
      
      # Stop all node services
      stop_management_nodes_service
      stop_sql_nodes_service
      stop_data_nodes_service
      stop_load_balancer_nodes_service
    end

    #---

    def restart_node_services
      $logger.log_action('Restarting Node Services', 'cluster')
      
      # Restart all node services
      restart_management_nodes_service
      restart_sql_nodes_service
      restart_data_nodes_service
      restart_load_balancer_nodes_service
    end

    #---

    def start_management_nodes_service
      command = 'ndb_mgmd -f /usr/local/mysql/mysql-cluster/config.ini'
      command << ' --initial' # initial startup, all data will be deleted
      node = get_cluster_management_node

      unless node.nil?
        text = "Starting Management-Service on VM (#{node['displayname']})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'management', command)

        sleep(3) # seconds
      end
    end

    #---

    def start_sql_nodes_service
      command = 'service mysql.server start'

      get_cluster_sql_nodes.each do |node|
        text = "Starting SQL-Service on VM (#{node['displayname']})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'sql', command)
      end

      sleep(3) # seconds
    end

    #---

    def start_data_nodes_service(initial_start = true)
      command = initial_start ? 'ndbd --initial' : 'ndbd'

      get_active_cluster_data_nodes.each do |node|
        text = "Starting Data-Service on VM (#{node['displayname']})."    
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'data', command)
      end

      sleep(3) # seconds
    end

    #---

    def start_load_balancer_nodes_service
      command = 'service haproxy start'
      node = get_cluster_load_balancer_node

      unless node.nil?
        displayname = node['displayname']
        text = "Starting Load-Balancing-Service on VM (#{displayname})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'loadbalancer', command)

        sleep(3) # seconds
      end
    end

    #---

    def stop_management_nodes_service
      command = "kill -9 $(ps aux | grep '[n]db_mgmd' | awk '{print $2}')"
      node = get_cluster_management_node

      unless node.nil?
        text = "Stopping Management-Service on VM (#{node['displayname']})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'management', command)
      end
    end

    #---

    def stop_sql_nodes_service
      command = "kill -9 $(ps aux | grep '[m]ysql' | awk '{print $2}')"

      get_cluster_sql_nodes.each do |node|
        text = "Stopping SQL-Service on VM (#{node['displayname']})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'sql', command)
      end
    end

    #---

    def stop_data_nodes_service
      command = "kill -9 $(ps aux | grep '[n]dbd' | awk '{print $2}')"

      get_active_cluster_data_nodes.each do |node|
        text = "Stopping Data-Service on VM (#{node['displayname']})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'data', command)
      end
    end

    #---

    def stop_load_balancer_nodes_service
      command = "kill -9 $(ps aux | grep '[h]aproxy' | awk '{print $2}')"
      node = get_cluster_load_balancer_node

      unless node.nil?
        displayname = node['displayname']
        text = "Stopping Load-Balancing-Service on VM (#{displayname})."
        $logger.log(text, 'cluster')

        execute_remote_command_on_node(node, 'loadbalancer', command)
      end
    end

    #---

    def restart_management_nodes_service
      $logger.log('Restarting Management-Nodes-Service.', 'cluster')

      stop_management_nodes_service
      start_management_nodes_service
    end

    #---

    def restart_sql_nodes_service
      $logger.log('Restarting SQL-Nodes-Service.', 'cluster')

      stop_sql_nodes_service
      start_sql_nodes_service
    end

    #---

    def restart_data_nodes_service
      $logger.log('Restarting Data-Nodes-Service.', 'cluster')

      stop_data_nodes_service
      start_data_nodes_service
    end

    #---

    def restart_load_balancer_nodes_service
      unless get_cluster_load_balancer_node.nil?
        $logger.log('Restarting Load-Balancer-Nodes-Service.', 'cluster')

        stop_load_balancer_nodes_service
        start_load_balancer_nodes_service
      end
    end

    #--------------------------------------------------------------------------
    # Cluster methods
    #--------------------------------------------------------------------------

    def reset_cluster
      root_dir = $utils.get_directory('..') + '/'
      log_dir = root_dir + CONFIG['logging']['dir']

      # Reset cluster configuration file
      $utils.empty_file(root_dir + CONFIG['configs']['cluster_nodes'])
      
      # Reset log files
      $utils.empty_file(log_dir + CONFIG['logging']['files']['benchmark'])
      $utils.empty_file(log_dir + CONFIG['logging']['files']['cluster'])
      $utils.empty_file(log_dir + CONFIG['logging']['files']['monitor'])
      $utils.empty_file(log_dir + CONFIG['logging']['files']['scaler'])
      $utils.empty_file(log_dir + CONFIG['logging']['files']['simulator'])

      $memorizer.reset('cluster_status')
      $logger.log('Cluster has been resetted.', 'cluster')

      true
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------

    def is_node_online?(id)
      node_type = get_node_type(id)
      
      host = get_vm(id)['nic'][0]['ipaddress']
      user = CONFIG['credentials'][node_type]['ssh']['user']
      password = CONFIG['credentials'][node_type]['ssh']['password']
      
      $communicator.is_ssh_reachable?(host, user, password)
    end

    #---

    def get_async_job_result(job_id)
      cloudstack = $communicator.connect_to_cloudstack
      
      cloudstack.query_async_job_result({
        :jobid => job_id
      })
    end

    #---

    def identify_mysql_host
      sql_nodes = get_cluster_sql_nodes
      load_balancer_node = get_cluster_load_balancer_node

      if load_balancer_node.nil?
        sql_nodes.first['ip']
      else
        load_balancer_node['ip']
      end
    end

    #---

    def shutdown_inactive_cluster_data_nodes
      nodes = get_inactive_cluster_data_nodes

      if !nodes.empty?
        text = 'Shutting Down Inactive Cluster Data Nodes'
        $logger.log_action(text, 'cluster')

        nodes.each do |node|
          stop_vm(node['id'])
        end
      end
    end

    #---

    def get_node_count_per_nodegroup
      nodes = get_active_cluster_data_nodes
      node_groups = []

      nodes.each do |node|
        node_groups << node['nodegroup']
      end

      nodes.count / node_groups.uniq.count
    end

    #---

    def get_cluster_capacity
      allowed_states = ['online', 'importing']
      return '-1MB' unless allowed_states.include?($memorizer.cluster_status)

      data_memory_size = CONFIG['settings']['data']['data_memory_size']
      data_memory_size = data_memory_size.delete('MB').to_f
      
      # Count distinct node groups
      active_cluster_data_nodes = get_active_cluster_data_nodes 
      node_groups = []
      
      active_cluster_data_nodes.each do |node|
        node_groups << node['nodegroup']
      end

      node_group_count = node_groups.uniq.size

      capacity = data_memory_size * node_group_count

      "#{capacity}MB"
    end

    #---

    def find_highest_existing_node_group
      data_nodes = get_active_cluster_data_nodes
      node_groups = [] 

      data_nodes.each do |node|
        node_groups << node['nodegroup']
      end

      node_groups.uniq.max
    end

    #---

    def get_cluster_ssh_ndb_mgm_nodes
      allowed_states = ['online', 'importing', 'scaling_up', 'scaling_down']
      return unless allowed_states.include?($memorizer.cluster_status)

      host = get_cluster_management_node['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']
      output = ''

      $communicator.query_ssh(host, user, password) do |ssh|
        output = ssh.exec!("ndb_mgm -e 'SHOW'")
      end

      output.gsub("\n", '<br>')

    rescue
      # this methody typically runs in a loop until it executes successfully
      # --> do nothing here
    end
    
    #---
    
    def get_cluster_ssh_ndb_mgm_memory_distribution
      allowed_states = ['online', 'importing', 'scaling_up', 'scaling_down']
      return unless allowed_states.include?($memorizer.cluster_status)

      host = get_cluster_management_node['ip']
      user = CONFIG['credentials']['management']['ssh']['user']
      password = CONFIG['credentials']['management']['ssh']['password']
      output = ''

      $communicator.query_ssh(host, user, password) do |ssh|
        output = ssh.exec!("ndb_mgm -e 'ALL REPORT MEMORY'")
      end

      output.gsub("\n", '<br>')

    rescue
      # this methody typically runs in a loop until it executes successfully
      # --> do nothing here
    end

    #---

    def get_node_type(id)
      node_types = $configurator.get_cluster_nodes_config

      node_types.each do |node_type, nodes|
        nodes.each do |key, values|
          if id == values['id']
            return node_type
          end
        end
      end

      nil
    end

    #---

    def execute_remote_command_on_node(node, node_type, command)
      host = node['ip']
      user = CONFIG['credentials'][node_type]['ssh']['user']
      password = CONFIG['credentials'][node_type]['ssh']['password']
      
      # Connect via SSH
      $communicator.query_ssh(host, user, password) do |ssh|
        ssh.exec!(command)
      end
    end

    #---

  end
end

#------------------------------------------------------------------------------

$manager = ADAPT::Manager.instance
