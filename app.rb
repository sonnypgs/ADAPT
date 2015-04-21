# encoding: utf-8
#------------------------------------------------------------------------------

require 'sinatra'
require 'sinatra/assetpack'
require 'sinatra/json'
require 'sinatra/flash'
require 'warden'
require 'sass'
require 'require_all'
require_all 'lib'
require_all 'routes'

#------------------------------------------------------------------------------

ADAPT::Logger.instance.log('ADAPT has been started.', 'adapt')

#------------------------------------------------------------------------------

ADAPT::Monitor.instance.monitor_cluster

#------------------------------------------------------------------------------

class Adapt < Sinatra::Base
  set :sessions, true
  set :session_secret, ADAPT::Utilities.get_config['adapt']['session_secret']
  set :environment, :production
  set :views, settings.root + '/views'
  set :erb, :layout => :'layouts/default'

  #----------------------------------------------------------------------------

  register Sinatra::AssetPack

  assets do
    serve '/js',      from: 'assets/scripts'
    serve '/css',     from: 'assets/stylesheets'
    serve '/images',  from: 'assets/images'
    serve '/comp',    from: 'assets/components'

    js :app, [
      '/js/all.js',
      '/js/shared.js',
      '/js/cloudstack.js',
      '/js/configuration.js',
      '/js/logging.js',
      '/js/monitor.js',
      '/js/simulation.js',
    ]

    css :default, [
      '/css/default.css'
    ]

    css :alternative, [
      '/css/alternative.css'
    ]

    js_compression  :jsmin
    css_compression :simple
  end

  #----------------------------------------------------------------------------

  register Sinatra::Flash

  #----------------------------------------------------------------------------

  use Warden::Manager do |config|
    config.serialize_into_session{|user| user }
    config.serialize_from_session{|user| user }
    config.scope_defaults :default,
    strategies: [:password],
    action: 'unauthenticated'
    config.failure_app = Adapt
  end

  Warden::Manager.before_failure do |env,opts|
    env['REQUEST_METHOD'] = 'POST'
  end

  #----------------------------------------------------------------------------

  Warden::Strategies.add(:password) do
    def valid?
      params['user'] && params['user']['username'] && params['user']['password']
    end

    def authenticate!
      user = {}
      user[:username] = params['user']['username']
      user[:password] = params['user']['password']
      config = ADAPT::Utilities.get_config
      config_username = config['adapt']['authentication']['username']
      config_password = config['adapt']['authentication']['password']

      if user[:username] == config_username && user[:password] == config_password
        success!(user)
      else
        fail!("Login-Daten falsch!")
      end
    end
  end

  #----------------------------------------------------------------------------

  register Sinatra::Adapt::Routes::Standard
  register Sinatra::Adapt::Routes::Functional
  register Sinatra::Adapt::Routes::Ajax
  register Sinatra::Adapt::Routes::Authentication

end