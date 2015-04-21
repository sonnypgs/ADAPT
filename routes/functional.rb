# encoding: utf-8
#----------------------------------------------------------------------------

module Sinatra::Adapt::Routes::Functional
  def self.registered(app)

    #---

    app.get '/monitor' do
      env['warden'].authenticate!

      @monitor = 'active'
      @title = 'Monitor'

      erb :monitor
    end

    #---

    app.get '/cloudstack' do
      env['warden'].authenticate!

      communicator = ADAPT::Communicator.instance
      manager = ADAPT::Manager.instance

      @url = communicator.get_cs_url
      @api_key = communicator.get_cs_api_key
      @secret_key = communicator.get_cs_secret_key
      @vms = manager.get_all_vms

      @cloudstack = 'active'
      @title = 'CloudStack'

      erb :cloudstack
    end

    #---

    app.get '/simulation' do
      env['warden'].authenticate!
      
      @simulation = 'active'
      @title = 'Simulation'

      erb :'simulation'
    end

    #---

    app.get '/configuration' do
      env['warden'].authenticate!

      manager = ADAPT::Manager.instance 

      @vms = manager.get_non_cluster_vms
      @management_node = manager.get_cluster_management_node
      @data_nodes = manager.get_cluster_data_nodes
      @sql_nodes = manager.get_cluster_sql_nodes
      @load_balancer_node = manager.get_cluster_load_balancer_node
      
      @configuration = 'active'
      @title = 'Konfiguration'

      erb :'configuration'
    end

    #---

    app.get '/logging' do
      env['warden'].authenticate!

      logger = ADAPT::Logger.instance

      @log_files = logger.list_log_files

      @logging = 'active'
      @title = 'Logging'

      erb :'logging'
    end

    #---
    
  end
end