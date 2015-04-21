# encoding: utf-8
#----------------------------------------------------------------------------

module Sinatra::Adapt::Routes::Standard
  def self.registered(app)

    #---

    app.get '/' do
      redirect to('/monitor')
    end

    #---

    app.get '/help' do
      env['warden'].authenticate!

      @help = 'active'
      @title = 'Hilfe'
      
      erb :help
    end

    #---

    app.not_found do
      env['warden'].authenticate!

      @not_found = 'active'
      @title = '404'

      erb :not_found, :layout => :'layouts/alternative'
    end

    #---
    
  end
end