# encoding: utf-8
#----------------------------------------------------------------------------

module Sinatra::Adapt::Routes::Authentication
	def self.registered(app)
	 
    #---

    app.get '/login' do
      if env['warden'].user.nil?
        @title = 'Login'

        erb :login, :layout => :'layouts/alternative'
      else
        redirect '/'
      end
    end

    #---

    app.post '/login' do
      env['warden'].authenticate!

      flash[:success] = env['warden'].message
      
      redirect '/'
    end

    #---

    app.post '/unauthenticated' do
      message = 'Login-Daten falsch oder nicht eingeloggt!'
      flash[:error] = env['warden'].message || message
      
      redirect '/login'
    end

    #---

    app.get '/logout' do
      env['warden'].logout
      flash[:success] = 'Erfolgreich abgemeldet'
      
      redirect '/login'
    end

    #---
    
	end
end