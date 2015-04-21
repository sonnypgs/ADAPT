#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'fileutils'
  require 'yaml'

  #----------------------------------------------------------------------------
  # Module
  #----------------------------------------------------------------------------

  module Utilities
    module_function

    #--------------------------------------------------------------------------
    # File & Directory methods
    #--------------------------------------------------------------------------

    def get_directory(prefix='')
      File.expand_path(prefix, File.dirname(__FILE__))
    end

    #---

    def empty_file(file)
      File.open(file, 'w') {}
    end

    #---

    def is_file_empty?(file)
      File.zero?(file)
    end

    #---

    def copy_file_to_destination(file, destination)
      FileUtils.copy(file, destination)
    end

    #---

    def replace_file_with_file(original_f, new_f)
      # Delete original
      File.delete(original_f) if File.exist?(original_f)
      
      # Copy new one to original one's place
      copy_file_to_destination(new_f, original_f)
    end

    #---

    def replace_text_in_file(file, original_t, new_t)
      new_content = get_file_content(file).gsub(original_t, new_t)
      
      File.open(file, 'w') do |f|
        f.puts new_content
      end
    end

    #---

    def get_file_line_count(file)
      count = 0
      
      File.open(file) do |f| 
        count = f.read.count("\n")
      end
    end

    #---

    def get_file_content(file)
      content = File.open(file) do |f| 
        f.read
      end
    end

    #---

    def write_to_file(file, text, method='w')
      File.open(file, 'w') do |f|
        f.puts text
      end
    end

    #---

    def append_to_file(file, text, method='a')
      File.open(file, 'a') do |f|
        f.puts text
      end
    end

    #---

    def list_files_in_dir(dir_path)
      Dir.entries(dir_path)
    end

    #--------------------------------------------------------------------------
    # Time methods
    #--------------------------------------------------------------------------

    def get_current_date_time
      Time.now.utc
    end

    #--------------------------------------------------------------------------
    # Config methods
    #--------------------------------------------------------------------------

    def get_config
      dir = get_directory '..'
      YAML.load_file "#{dir}/configs/config.yaml"
    end

    #--------------------------------------------------------------------------
    # Debug methods
    #--------------------------------------------------------------------------

    def debug(text)
      p text # prints to the console window
    end

    #---
    
  end
end

#------------------------------------------------------------------------------

$utils = ADAPT::Utilities