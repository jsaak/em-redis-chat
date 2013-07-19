#!/usr/bin/env ruby

require 'em-hiredis'
require 'eventmachine'
require 'singleton'
require 'socket'

class ChatServer
   include Singleton

   UserInfo = Struct.new(:ip,:connection)

   def initialize
      @redis = EM::Hiredis.connect
      @pubsub = @redis.pubsub
      @users = {}
   end

   def connect(nick,ip,conn)
      if @users[nick].nil?
         @users[nick] = UserInfo.new(ip,conn)
         @pubsub.subscribe('default').callback do
            @pubsub.on(:message) do |channel, message|
               conn.send_data message
            end
            @redis.publish('default',"#{nick} has connected\n")
         end
         return true
      else
         conn.send_data "nick already taken, enter a different username: "
         return false
      end
   end

   def disconnect(nick)
      @redis.publish('default',"#{nick} has disconnected\n")
      @pubsub.unsubscribe('default')
      @users.delete nick
   end

   def say(nick,message)
      @redis.publish('default',nick + ': ' + message + "\n")
   end

   def whisper(conn,nick,dest_nick,message)
      if @users[dest_nick].nil?
         conn.send_data "unknown user: #{dest_nick}\n"
      else
         dest_conn = @users[dest_nick].connection
         dest_conn.send_data "[whispering] #{nick}: #{message}\n"
      end
   end

   def user_list(conn)
      @users.each do |nick,ui|
         conn.send_data nick + ' ' + ui.ip + "\n"
      end
   end
end

module ChatConnection
   def post_init
      send_data "Welcome to ChatServer\n"
      send_data 'enter your nickname: '
      port, @ip = Socket.unpack_sockaddr_in(get_peername)
   end

   def unbind
      ChatServer.instance.disconnect(@nick) unless @nick.nil?
   end

   def receive_data(data)
      data.strip.split("\n").each do |line|
         if @nick.nil?
            # login
            nick = line
            if ChatServer.instance.connect(nick,@ip,self)
               @nick = nick
            end
         elsif line[0..0] == "/"
            # process commands
            command, *params = line[1..-1].split
            case command
            when 'quit'
               close_connection()
            when 'users'
               ChatServer.instance.user_list(self)
            when 'query'
               ChatServer.instance.whisper(self,@nick,params[0],params[1..-1].join(' '))
            else
               send_data 'unsupported command: ' + command + "\n"
            end
         else
            # chat
            ChatServer.instance.say(@nick,line)
         end
      end
   end
end

EM.run do
   stop_func = proc {
      puts "\nstopping server"
      EventMachine.stop
   }
   Signal.trap("INT",stop_func)
   Signal.trap("TERM",stop_func)

   port = 2222
   EventMachine.start_server("0.0.0.0", port, ChatConnection)

   puts "server running at localhost: #{port}"
end
