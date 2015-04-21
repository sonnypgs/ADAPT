# encoding: utf-8
#----------------------------------------------------------------------------

module Sinatra::Adapt::Routes::Ajax
  def self.registered(app)

    #--------------------------------------------------------------------------
    # Monitor
    #--------------------------------------------------------------------------

    app.get '/cluster_metrics' do
      env['warden'].authenticate!

      memorizer = ADAPT::Memorizer.instance
      scaler = ADAPT::Scaler.instance
      manager = ADAPT::Manager.instance

      status = memorizer.cluster_status

      latency = memorizer.cluster_latency
      latency = latency.delete('ms').to_f

      fast_average_latency = memorizer.cluster_fast_average_latency
      fast_average_latency = fast_average_latency.delete('ms').to_f
      
      slow_average_latency = memorizer.cluster_slow_average_latency
      slow_average_latency = slow_average_latency.delete('ms').to_f

      capacity = manager.get_cluster_capacity
      capacity = capacity.delete('MB').to_f
      
      capacity_used = memorizer.cluster_used_capacity
      capacity_used = capacity_used.delete('MB').to_f

      capacity_scale_up = scaler.calculate_scale_up_capacity
      capacity_scale_down = scaler.caculate_scale_down_capacity

      cluster_nodes = manager.get_cluster_ssh_ndb_mgm_nodes
      
      memory_distribution = manager.get_cluster_ssh_ndb_mgm_memory_distribution

      json :result => {
        'cluster_status'                  => status,
        'cluster_latency'                 => latency,
        'cluster_fast_average_latency'    => fast_average_latency,
        'cluster_slow_average_latency'    => slow_average_latency,
        'cluster_capacity'                => capacity,
        'cluster_capacity_used'           => capacity_used,
        'cluster_capacity_scale_up'       => capacity_scale_up,
        'cluster_capacity_scale_down'     => capacity_scale_down,
        'cluster_nodes'                   => cluster_nodes,
        'cluster_memory_distribution'     => memory_distribution
      }      
    end

    #---

    app.get '/cluster_status' do
      env['warden'].authenticate!

      cluster_status = ADAPT::Memorizer.instance.cluster_status

      json :result => cluster_status      
    end

    #--------------------------------------------------------------------------
    # CloudStack
    #--------------------------------------------------------------------------

    app.get '/start_vm' do
      env['warden'].authenticate!

      manager = ADAPT::Manager.instance
      vm_id = params[:vmId]
      result = manager.start_vm(vm_id)

      if not result[:job_id].nil?
        json :result => result[:job_id]
      else
        json :error  => result[:error]
      end
    end

    #---

    app.get '/stop_vm' do
      env['warden'].authenticate!

      manager = ADAPT::Manager.instance
      vm_id = params[:vmId]

      result = manager.stop_vm(vm_id)

      if not result[:job_id].nil?
        json :result => result[:job_id]
      else
        json :error  => result[:error]
      end
    end

    #---

    app.get '/reboot_vm' do
      env['warden'].authenticate!

      manager = ADAPT::Manager.instance
      vm_id = params[:vmId]

      result = manager.reboot_vm(vm_id)

      if not result[:job_id].nil?
        json :result => result[:job_id]
      else
        json :error  => result[:error]
      end
    end

    #--------------------------------------------------------------------------
    # Configuration
    #--------------------------------------------------------------------------

    app.get '/configure_cluster' do
      env['warden'].authenticate!
      
      nodes = {
        'management'    => params[:managementNode],
        'sql'           => params[:sqlNodes],
        'data'          => params[:dataNodes],
        'loadbalancer'  => params[:loadBalancerNode]
      }

      configurator = ADAPT::Configurator.instance
      result = configurator.update_cluster_configuration nodes
      
      json :result => result
    end

    #---

    app.get '/async_job_result' do
      env['warden'].authenticate!

      job_id = params[:jobId]
      job_result = ADAPT::Manager.instance.get_async_job_result(job_id)
      
      json :result => job_result
    end

    #--------------------------------------------------------------------------
    # Simulation
    #--------------------------------------------------------------------------

    app.get '/start_simulator' do
      env['warden'].authenticate!

      query = params[:query]
      query_count = params[:queryCount].to_i
      thread_count = params[:threadCount].to_i

      simulator = ADAPT::Simulator.instance
      benchmark_result = simulator.benchmark(query, query_count, thread_count)
      
      json :result => {
        'benchmark_result' => benchmark_result
      }
    end

    #---

    app.get '/simulator_status' do
      env['warden'].authenticate!

      query_count = params[:queryCount].to_i
      thread_count = params[:threadCount].to_i

      simulator = ADAPT::Simulator.instance
      progress = simulator.get_progress_percentage(query_count, thread_count)

      json :result => progress
    end

    #---

    app.get '/import_cluster_test_database' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      import_success = simulator.import_cluster_test_database

      json :result => import_success
    end

    #---

    app.get '/is_cluster_test_database_imported' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      imported = simulator.is_cluster_test_database_imported?

      json :result => imported
    end

    #---

    app.get '/delete_cluster_test_database' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      simulator.delete_cluster_test_database

      json :result => 'success'
    end

    #---

    app.get '/data_record_count' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      result = simulator.get_data_record_count
      
      json :result => result
    end 

    #---

    app.get '/insert_into_database_until_scaling' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      result = simulator.insert_into_database_until_scaling
      
      json :result => result
    end   

    #---

    app.get '/remove_from_database_until_scaling' do
      env['warden'].authenticate!

      simulator = ADAPT::Simulator.instance
      result = simulator.remove_from_database_until_scaling
      
      json :result => result
    end     

    #--------------------------------------------------------------------------
    # Logging
    #--------------------------------------------------------------------------

    app.get '/log_file' do
      env['warden'].authenticate!

      log_file_name = params[:logFileName]
      logger = ADAPT::Logger.instance
      log_file_content = logger.read_log_file(log_file_name)

      json :result => log_file_content
    end

    #--------------------------------------------------------------------------
    # Misc
    #--------------------------------------------------------------------------

    app.get '/reset_cluster' do
      env['warden'].authenticate!
      
      reset = ADAPT::Manager.instance.reset_cluster

      json :result => reset
    end

    #---

  end
end