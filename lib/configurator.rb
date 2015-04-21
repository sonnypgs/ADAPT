#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'singleton'
  require 'yaml'
  require_relative 'communicator'
  require_relative 'logger'
  require_relative 'manager'
  require_relative 'memorizer'
  require_relative 'simulator'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Configurator

    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------

    include Singleton
    
    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------

    CONFIG = $utils.get_config
    CLUSTER_NODES_CONFIG = CONFIG['configs']['cluster_nodes']
    DIR = $utils.get_directory('..') + '/'

    #--------------------------------------------------------------------------
    # Main methods
    #--------------------------------------------------------------------------

    def update_cluster_configuration(nodes)
      nodes = map_nodeids nodes # required later for configs
      cluster_nodes_config = get_cluster_nodes_config

      # Check if the configuration has been changed since last time
      if (nodes != cluster_nodes_config)
        # Reset saved cluster values
        $memorizer.reset('cluster_latency')
        $memorizer.reset('cluster_used_capacity')
        $memorizer.reset('cluster_status')
        $memorizer.reset('scale_up_attempts')
        $memorizer.reset('scale_down_attempts')

        # Save the configuration to a local config file
        write_cluster_nodes_config(nodes.to_yaml)
        $memorizer.cluster_status = 'configuring'
        $logger.log_state('Cluster is configuring', 'cluster')

        # Make sure that all required cluster nodes are online (SSH),
        #  so the remote configuration files can be replaced
        $manager.ensure_that_cluster_nodes_are_online

        # Delete the imported cluster test database if it exists
        $simulator.delete_cluster_test_database

        # Update the remote configurations as soon as all nodes are online
        update_node_configs(nodes)
        
        # Shutdown inactive (currently not needed) data nodes to save resources
        $manager.shutdown_inactive_cluster_data_nodes

        # Cluster is configured
        $memorizer.cluster_status = 'configured'
        $logger.log_state('Cluster is configured', 'cluster')

        # Optional timeout
        sleep(2) # seconds
        
        # Restart all node services so the new configurations will be loaded 
        $memorizer.cluster_status = 'starting'
        $logger.log_state('Cluster is starting', 'cluster')
        $manager.restart_node_services

        'updated'

      else
        # Do nothing if the configuration hasn't been changed
        'no_changes'
      end
    end

    #---

    def update_node_configs(nodes)
      $logger.log_action('Replacing Node Configurations', 'cluster')

      # Update all node configurations
      update_ndb_mgmd_config(nodes)
      update_mysqld_config(nodes)
      update_ndbd_config(nodes)
      update_haproxy_config(nodes)
    end

    #--------------------------------------------------------------------------
    # Configuration files methods
    #--------------------------------------------------------------------------

    def update_ndb_mgmd_config(nodes)  
      # Prepare ndbd_default segment
      number_of_replica = calculate_number_of_replica nodes['data']
      data_memory_size  = CONFIG['settings']['data']['data_memory_size']
      index_memory_size = CONFIG['settings']['data']['index_memory_size']
      data_dir          = CONFIG['settings']['data']['data_dir']
      ndbd_default = %Q(
        [ndbd default]
        NoOfReplicas=#{number_of_replica}
        DataMemory=#{data_memory_size}
        IndexMemory=#{index_memory_size}
        DataDir=#{data_dir}
      )
      
      # Prepare ndb_mgmd segment
      management_nodeid = CONFIG['settings']['management']['nodeid']
      management_node_data_dir = CONFIG['settings']['management']['data_dir']
      management_node = %Q(
        [ndb_mgmd]
        NodeId=#{management_nodeid}
        HostName=#{nodes['management'][management_nodeid]['ip']}
        DataDir=#{management_node_data_dir}
      )
  
      # Prepare mysqlds segment
      sql_nodes = ''

      nodes['sql'].each do |node|
        sql_nodes << %Q(
          [mysqld]
          NodeId=#{node[0]}
          HostName=#{node[1]['ip']}
        )
      end

      # Prepare ndbds segment
      data_nodes = ''

      nodes['data'].each do |node|
        data_nodes << %Q(
          [ndbd]
          NodeId=#{node[0]}
          HostName=#{node[1]['ip']}
          Nodegroup=#{node[1]['nodegroup']}
        )
      end

      # Copy local template file
      node_type = 'management'
      
      config_dir = CONFIG['configs']['local']['dir']
      config_file = CONFIG['configs']['local']['files'][node_type]
      config_file = DIR + config_dir + config_file
      
      template_dir = CONFIG['configs']['template']['dir']
      template_file = CONFIG['configs']['template']['files'][node_type]
      template_file = DIR + template_dir + template_file

      $utils.replace_file_with_file(config_file, template_file)

      # Replace markers in copied template file
      markers = {
        '<ndbd_default>'  => ndbd_default,
        '<ndb_mgmd>'      => management_node,
        '<mysqlds>'       => sql_nodes,
        '<ndbds>'         => data_nodes
      }

      markers.each do |key, value|
        $utils.replace_text_in_file(config_file, key, value.to_s)
      end

      # Transmit updated config file to all management nodes
      replace_remote_config(node_type, nodes)
    end

    #---

    def update_mysqld_config(nodes)
      # Prepare mysqld segment
      mysqld = %Q(
        [mysqld]
        ndbcluster
        ndb-connectstring=#{nodes['management'].first[1]['ip']}
        ndb-cluster-connection-pool=1
        bind-address = 0.0.0.0
        max_connect_errors = 10000
      )
  
      # Prepare mysql_cluster segment
      mysql_cluster = %Q(
        [mysql_cluster]
        ndb-connectstring=#{nodes['management'].first[1]['ip']}
      )

      # Copy local template file
      node_type = 'sql'

      config_dir = CONFIG['configs']['local']['dir']
      config_file = CONFIG['configs']['local']['files'][node_type]
      config_file = DIR + config_dir + config_file
      
      template_dir = CONFIG['configs']['template']['dir']
      template_file = CONFIG['configs']['template']['files'][node_type]
      template_file = DIR + template_dir + template_file

      $utils.replace_file_with_file(config_file, template_file)

      # Replace markers in copied template file
      markers = {
        '<mysqld>'        => mysqld,
        '<mysql_cluster>' => mysql_cluster
      }

      markers.each do |key, value|
        $utils.replace_text_in_file(config_file, key, value.to_s)
      end

      # Transmit updated config file to all sql nodes
      replace_remote_config(node_type, nodes)
    end

    #---

    def update_ndbd_config(nodes)
      # Prepare mysql segment
      mysqld = %Q(
        [mysqld]
        ndbcluster
        ndb-connectstring=#{nodes['management'].first[1]['ip']}
      )
  
      # Prepare mysql_cluster segment
      mysql_cluster = %Q(
        [mysql_cluster]
        ndb-connectstring=#{nodes['management'].first[1]['ip']}
      )

      # Copy local template file
      node_type = 'data'

      config_dir = CONFIG['configs']['local']['dir']
      config_file = CONFIG['configs']['local']['files'][node_type]
      config_file = DIR + config_dir + config_file
      
      template_dir = CONFIG['configs']['template']['dir']
      template_file = CONFIG['configs']['template']['files'][node_type]
      template_file = DIR + template_dir + template_file

      $utils.replace_file_with_file(config_file, template_file)

      # Replace markers in copied template file
      markers = {
        '<mysqld>'        => mysqld,
        '<mysql_cluster>' => mysql_cluster
      }

      markers.each do |key, value|
        $utils.replace_text_in_file(config_file, key, value.to_s)
      end

      # Transmit updated config file to all data nodes
      replace_remote_config(node_type, nodes)
    end

    #---

    def update_haproxy_config(nodes)
      # Check if a load balancer has been defined
      if nodes['loadbalancer'].length > 0
        load_balancer_ip = nodes['loadbalancer'].first[1]['ip']

        sql_nodes = ''
        sql_node_id = 1
        sql_port = CONFIG['settings']['sql']['port']

        nodes['sql'].each do |node|
          sql_nodes << %Q(
            server sql#{sql_node_id} #{node[1]['ip']}:#{sql_port} check
          )
          sql_node_id = sql_node_id + 1
        end

        # Copy local template file
        node_type = 'loadbalancer'

        config_dir = CONFIG['configs']['local']['dir']
        config_file = CONFIG['configs']['local']['files'][node_type]
        config_file = DIR + config_dir + config_file
        
        template_dir = CONFIG['configs']['template']['dir']
        template_file = CONFIG['configs']['template']['files'][node_type]
        template_file = DIR + template_dir + template_file

        $utils.replace_file_with_file(config_file, template_file)

        # Replace markers in copied template file
        markers = {
          '<load-balancer-ip>'  => load_balancer_ip,
          '<sql-nodes>'         => sql_nodes
        }

        markers.each do |key, value|
          $utils.replace_text_in_file(config_file, key, value.to_s)
        end

        # Transmit updated config file to all load balancer nodes
        replace_remote_config(node_type, nodes)
      end
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------
    
    def map_nodeids(nodes)
      # For more details, please have a look at the nodeid-mapping diagram
      id_counter = CONFIG['settings']['management']['nodeid'] # default: 1
      nodes_new = {}

      nodes.each do |node_group|
        nodes_new[node_group[0]] = {}

        unless node_group[1].nil?
          node_group[1].each do |node|
            nodes_new[node_group[0]][id_counter] = node[1]
            id_counter += 1
          end
        end
      end

      nodes_new
    end

    #---

    def calculate_number_of_replica(data_nodes)
      node_group_numbers = []
      data_node_count = 0

      data_nodes.each do |node|
        nodegroup = node[1]['nodegroup'].to_i

        if nodegroup != 65536 # = inactive nodes
          node_group_numbers.push(nodegroup)
          data_node_count += 1
        end
      end

      node_group_numbers = node_group_numbers.uniq
      node_group_count = node_group_numbers.size

      (data_node_count / node_group_count) # = number_of_replica
    end

    #---

    def replace_remote_config(node_type, nodes)
      local_dir = DIR + CONFIG['configs']['local']['dir']

      nodes[node_type].each do |node|
        host = node[1]['ip']
        user = CONFIG['credentials'][node_type]['ssh']['user']
        password = CONFIG['credentials'][node_type]['ssh']['password']

        local_file = CONFIG['configs']['local']['files'][node_type]
        local_path = local_dir + local_file
        remote_path = CONFIG['configs']['remote']['paths'][node_type]
        
        # Transfer updated config via SCP
        $communicator.query_scp(host, user, password) do |scp|
          text = "Replacing config on VM (#{node[1]['displayname']})."
          $logger.log(text, 'cluster')

          scp.upload!(local_path, remote_path)
        end
      end
    end

    #---

    def get_cluster_nodes_config
      YAML.load_file(CLUSTER_NODES_CONFIG)
    end

    #---

    def write_cluster_nodes_config(content)
      $utils.write_to_file(CLUSTER_NODES_CONFIG, content)
    end

    #---
    
  end
end

#------------------------------------------------------------------------------

$configurator = ADAPT::Configurator.instance