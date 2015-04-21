#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------

  require 'singleton'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Memorizer

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

    attr_accessor :cluster_status
    attr_accessor :cluster_latency
    attr_accessor :cluster_fast_average_latency
    attr_accessor :cluster_slow_average_latency
    attr_accessor :cluster_used_capacity
    attr_accessor :scale_up_attempts
    attr_accessor :scale_down_attempts

    #--------------------------------------------------------------------------
    # Methods
    #--------------------------------------------------------------------------

    def initialize
      c = CONFIG['memorizer']

      @cluster_status = c['cluster_status_default']
      @cluster_latency = c['cluster_latency_default']
      @cluster_fast_average_latency = c['cluster_fast_average_latency_default']
      @cluster_slow_average_latency = c['cluster_slow_average_latency_default']
      @cluster_used_capacity = c['cluster_used_capacity_default']
      @scale_up_attempts = c['scale_up_attempts_default']
      @scale_down_attempts = c['scale_down_attempts_default']
    end

    #---

    def reset(key)
      value = CONFIG['memorizer']["#{key}_default"]
      instance_variable_set("@#{key}", value)
    end

    #---
    
  end
end

#------------------------------------------------------------------------------

$memorizer = ADAPT::Memorizer.instance
