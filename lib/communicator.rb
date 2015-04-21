#------------------------------------------------------------------------------
# Module
#------------------------------------------------------------------------------

module ADAPT

  #----------------------------------------------------------------------------
  # Requirements
  #----------------------------------------------------------------------------
  
  require 'cloudstack_ruby_client'
  require 'mysql2'
  require 'net/ssh'
  require 'net/scp'
  require 'singleton'
  require_relative 'logger'
  require_relative 'utilities'

  #----------------------------------------------------------------------------
  # Class
  #----------------------------------------------------------------------------

  class Communicator
    
    #--------------------------------------------------------------------------
    # Includes
    #--------------------------------------------------------------------------
    
    include Singleton

    #--------------------------------------------------------------------------
    # Constants
    #--------------------------------------------------------------------------
    
    CONFIG = $utils.get_config

    #--------------------------------------------------------------------------
    # CloudStack methods
    #--------------------------------------------------------------------------
    
    def connect_to_cloudstack
      url = get_cs_url
      api_key = get_cs_api_key
      secret_key = get_cs_secret_key

      CloudstackRubyClient::Client.new(url, api_key, secret_key, false)
    end

    #---

    def get_cs_url
      CONFIG['cloudstack']['url']
    end

    #---

    def get_cs_api_key
      CONFIG['cloudstack']['api_key']
    end

    #---

    def get_cs_secret_key
      CONFIG['cloudstack']['secret_key']
    end

    #--------------------------------------------------------------------------
    # SSH & SCP methods
    #--------------------------------------------------------------------------

    def query_ssh(host, user, password, &ssh)
      Net::SSH.start(host, user, :password => password) do |ssh|
        yield ssh
      end

      rescue Errno::ETIMEDOUT
        message = "SSH connection to #{host} has timed out."
        $logger.log_error(message, 'cluster')
      
      rescue Errno::ECONNREFUSED
        message = "SSH connection to #{host} refused."
        $logger.log_error(message, 'cluster')
      
      rescue Errno::EHOSTUNREACH
        message = "SSH connection to #{host} could not be established."
        $logger.log_error(message, 'cluster')
      
      rescue => error
        message = "SSH connection to #{host} failed because of: #{error}."
        $logger.log_error(message, 'cluster')
    end

    #---

    def is_ssh_reachable?(host, user, password)
      ssh_reachable = false
      
      query_ssh(host, user, password) do |ssh|
        ssh_reachable = true
      end

      ssh_reachable
    end

    #---

    def query_scp(host, user, password, &scp)
      Net::SCP.start(host, user, :password => password) do |scp|
        yield scp
      end
    end

    #--------------------------------------------------------------------------
    # MySQL methods
    #--------------------------------------------------------------------------

    def create_new_mysql_client(host)
      Mysql2::Client.new(
        :host       => host, 
        :username   => CONFIG['credentials']['sql']['mysql']['user'], 
        :password   => CONFIG['credentials']['sql']['mysql']['password']
      )
    rescue
      nil
    end

    #---
    
  end
end

#------------------------------------------------------------------------------

$communicator = ADAPT::Communicator.instance