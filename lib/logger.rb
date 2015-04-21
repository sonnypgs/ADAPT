#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'singleton'
  require 'yaml'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Logger

    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------

    include Singleton

    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------

    CONFIG = $utils.get_config
    LOG_DIR = CONFIG['logging']['dir']

    #--------------------------------------------------------------------------
    # Logging methods
    #--------------------------------------------------------------------------

    def log(text, file_type)
      path = LOG_DIR + CONFIG['logging']['files'][file_type]
      text = "#{$utils.get_current_date_time}  |  #{text}"
      
      $utils.append_to_file(path, text)
    end

    #---

    def log_error(text, file_type)
      text = "*Error* #{text}"
      log(text, file_type)
    end

    #---

    def log_info(text, file_type)
      text = "---> #{text}"
      log(text, file_type)
    end

    #---

    def log_state(text, file_type)
      text = "----> #{text} <----"
      log(text, file_type)
    end

    #---

    def log_action(text, file_type)
      text = "=== #{text} ==="
      log(text, file_type)
    end

    #--------------------------------------------------------------------------
    # Helper methods
    #--------------------------------------------------------------------------

    def read_log_file(log_file_name)
      path = LOG_DIR + log_file_name
      $utils.get_file_content(path)
    end

    #---

    def list_log_files
      dir = $utils.get_directory('..') + '/'
      all_files_in_dir = $utils.list_files_in_dir(dir + LOG_DIR)
      files_to_remove = ['.', '..', '.keep']
      
      all_files_in_dir - files_to_remove
    end

    #---

  end
end

#------------------------------------------------------------------------------

$logger = ADAPT::Logger.instance
