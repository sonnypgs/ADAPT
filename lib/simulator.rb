#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'benchmark'
  require 'singleton'
  require_relative 'communicator'
  require_relative 'logger'
  require_relative 'manager'
  require_relative 'memorizer'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Simulator

    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------

    include Singleton
    
    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------

    CONFIG = $utils.get_config
    LOGFILE = CONFIG['logging']['dir']+CONFIG['logging']['files']['benchmark']
    THREAD_COUNT = CONFIG['simulator']['thread_count']
    QUERY_COUNT = CONFIG['simulator']['query_count']

    #--------------------------------------------------------------------------
    # Main method
    #--------------------------------------------------------------------------

    def benchmark(query, query_count, thread_count)
      # Set defaults, if parameters are not set
      query = CONFIG['simulator']['query'] unless defined? query
      query_count = QUERY_COUNT unless defined? query_count
      thread_count = THREAD_COUNT unless defined? thread_count

      # Log a detailled message
      message = "Starting simulated stress test (benchmark) with"
      message += " #{thread_count} threads and #{query_count} queries"
      message += " per thread for the query: '#{query}'."
      $logger.log(message, 'simulator')

      # Empty the benchmark logfile first
      $utils.empty_file(LOGFILE)

      # Execute the simulation
      threads = []
      benchmark_results = []
      host = $manager.identify_mysql_host

      thread_count.times do |i| 
        threads << Thread.new(i) do

          client = $communicator.create_new_mysql_client(host)

          query_count.times do |j|
            time = Benchmark.realtime do
              client.query(query)
            end

            time = time * 1000 # transform seconds into milliseconds

            benchmark_results << time

            # Fill a log file (will be used to determine the progress)
            $utils.append_to_file(LOGFILE, "Thread #{i}: Query #{j}")
          end

          client.close

        end
      end

      threads.each do |t|
        t.join
      end

      (benchmark_results.reduce(:+) / benchmark_results.size) # = average_time
    
    rescue => error
      $logger.log_error("#{error}.", 'simulator')
      false
    end

    #--------------------------------------------------------------------------
    # Fill database methods
    #--------------------------------------------------------------------------

    def import_cluster_test_database
      $logger.log_state('Cluster is importing', 'cluster')
      $memorizer.cluster_status = 'importing'
      $logger.log_action('Importing Cluster Test Database', 'simulator')

      db_name = CONFIG['simulator']['database']['name']
      database_file_path = CONFIG['simulator']['database']['file_path']
      mysql = CONFIG['simulator']['database']['mysql']
      ssh_user = CONFIG['credentials']['sql']['ssh']['user']
      ssh_password = CONFIG['credentials']['sql']['ssh']['password']

      sql_nodes = $manager.get_cluster_sql_nodes

      # Create database (via MySQL)
      host = sql_nodes.first['ip']
      client = $communicator.create_new_mysql_client(host)
      
      $logger.log("Creating database '#{db_name}'.", 'simulator')
      
      client.query("CREATE DATABASE #{db_name}")
      client.close

      # Import sample data (via SSH)
      $communicator.query_ssh(host, ssh_user, ssh_password) do |ssh|
        ssh.open_channel do |channel|
          
          message = "Importing sample data for database '#{db_name}'."
          $logger.log(message, 'simulator')

          command = "#{mysql} #{db_name} < #{database_file_path}"

          channel.exec(command) do |ch, success|
            abort "*Error* Could not execute command." unless success
          end

          channel.on_data do |ch, data|
            # nothing to do
          end

          channel.on_extended_data do |ch, type, data|
            $logger.log_error("#{data}", 'simulator')
          end
        end
      end

      $logger.log_state('Cluster is online', 'cluster')
      $memorizer.cluster_status = 'online'
      
      true

    rescue => error
      $logger.log_error("#{error}.", 'simulator')

      $logger.log_state('Cluster is online', 'cluster')
      $memorizer.cluster_status = 'online'

      false
    end

    #---

    def insert_into_database_until_scaling
      $logger.log_action('Inserting Into Database', 'simulator')

      host = $manager.identify_mysql_host
      thread_count = CONFIG['simulator']['database']['insert']['threads']
      insert_count = CONFIG['simulator']['database']['insert']['times']

      thread_count.times do
        Thread.new do
          client = $communicator.create_new_mysql_client(host)

          insert_count.times do
            insert_random_data_set(client)
          end

          client.close
        end
      end

      true

    rescue => error
      $logger.log_error("#{error}.", 'simulator')
      false
    end

    #---

    def insert_random_data_set(client)
      db_name = CONFIG['simulator']['database']['name']
      table_name = 'CUSTOMER'
      test = 'TESTTESTTEST'
      random_id = rand(1_000_000..4_000_000)

      command = "INSERT INTO #{db_name}.#{table_name}"
      command << " (C_ID, C_UNAME, C_PASSWD,C_FNAME, C_LNAME,"
      command << " C_PHONE, C_EMAIL, C_DATA)"
      command << " VALUES (#{random_id}, 'TEST', '#{test}', '#{test}',"
      command << " '#{test}', '#{test}', '#{test}', '#{test}')"
      
      client.query(command)
    
    rescue => error
      $logger.log_error("#{error}.", 'simulator')
    end

    #--------------------------------------------------------------------------
    # Empty database methods
    #--------------------------------------------------------------------------

    def delete_cluster_test_database
      $logger.log_action('Deleting Cluster Test Database', 'simulator')
      
      db_name = CONFIG['simulator']['database']['name']
      sql_nodes = $manager.get_cluster_sql_nodes

      # Delete existing test databases on all sql nodes

      sql_nodes.each do |node|
        host = node['ip']
        client = $communicator.create_new_mysql_client(host)

        unless client.nil?
          $logger.log("Removing database '#{db_name}'.", 'simulator')

          client.query("DROP DATABASE IF EXISTS #{db_name}")
          
          client.close
        end
      end
      
    rescue => error
      $logger.log_error(error, 'simulator')
    end

    #---

    def remove_from_database_until_scaling
      $logger.log_action('Deleting From Database', 'simulator')

      host = $manager.identify_mysql_host
      client = $communicator.create_new_mysql_client(host)
      drop_table(client, 'ADDRESS')

      true

    rescue => error
      $logger.log_error("#{error}.", 'simulator')
      false
    end
   
   #---

    def drop_table(client, table_name)
      db_name = CONFIG['simulator']['database']['name']
        
      $logger.log("Dropping table '#{db_name}.#{table_name}'.", 'simulator')
      client.query("DROP TABLE #{db_name}.#{table_name}")

    rescue => error
      $logger.log_error("#{error}.", 'simulator')      
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------

    def get_data_record_count
      host = $manager.identify_mysql_host
      client = $communicator.create_new_mysql_client(host)
      db_name = CONFIG['simulator']['database']['name']

      # Retrieve table names
      tables = []
      results = client.query("SHOW TABLES FROM #{db_name}")
      
      results.each do |result|
        tables << result.to_a[0][1]
      end

      # Retrieve data count for each table
      counts = {}

      tables.each do |table|
        result = client.query("SELECT COUNT(*) FROM #{db_name}.#{table}")
        counts["#{table.downcase}_count"] = result.to_a[0].values[0]
      end

      client.close

      counts

    rescue => error
      $logger.log_error("#{error}.", 'simulator')
      false
    end

    #---

    def get_progress_percentage(query_count, thread_count)
      query_count = QUERY_COUNT unless defined? query_count
      thread_count = THREAD_COUNT unless defined? thread_count

      line_count = $utils.get_file_line_count(LOGFILE)
      expected_overall_line_count = thread_count * query_count

      (line_count.fdiv(expected_overall_line_count) * 100).floor
    end

    #---

    def is_cluster_test_database_imported?
      host = $manager.identify_mysql_host
      client = $communicator.create_new_mysql_client(host)
      db_name = CONFIG['simulator']['database']['name']

      client.query("USE #{db_name}")
      client.close
      
      true

    rescue
      false
    end

    #---

  end
end

#------------------------------------------------------------------------------

$simulator = ADAPT::Simulator.instance
