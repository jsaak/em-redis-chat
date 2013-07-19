require "minitest/autorun"
require 'net/telnet'
require 'socket'

class TestChatServer < Minitest::Unit::TestCase
   PORT = 2222
   HOST = 'localhost'

   def setup
      @pid = spawn('./server.rb', :out=>"/dev/null")
      @clients = {}
   end

   def teardown
      Process.kill(:SIGINT, @pid)
      Process.wait @pid
   end

   def wait_for_socket
      begin
         s = TCPSocket.new(HOST,PORT)
         s.close
         return
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
         sleep(0.05)
         retry
      end
   end

   def login(nick)
      wait_for_socket()
      client = Net::Telnet::new("Host" => "localhost", "Port" => 2222, "Telnetmode" => false, "Binmode" => true)
      client.waitfor("String" => 'enter your nickname')
      client.puts(nick)
      @clients[nick] = client
   end

   def logout(nick)
      @clients[nick].close
   end

   def say(nick,message)
      @clients[nick].puts(message)
   end

   def recieve(nick)
      @clients[nick].waitfor("Match" => /..*/, 'Timeout' => 10) do |s|
        return s
      end
   end

   def test_simple_login
      login 'feri'
      assert_equal "feri has connected\n", recieve('feri')
      logout 'feri'
   end

   def login_2_users
      login 'feri'
      assert_equal "feri has connected\n", recieve('feri')
      login 'geza'
      assert_equal "geza has connected\n", recieve('feri')
      assert_equal "geza has connected\n", recieve('geza')
   end

   def logout_2_users
      logout 'feri'
      assert_equal "feri has disconnected\n", recieve('geza')
      logout 'geza'
   end

   def test_multiple_login
      login_2_users
      logout_2_users
   end

   def test_basic_chat
      login_2_users
      say 'feri', 'hello world'
      assert_equal "feri: hello world\n", recieve('feri')
      assert_equal "feri: hello world\n", recieve('geza')
      logout_2_users
   end

   def test_whisper
      login_2_users
      say 'feri', '/query geza whispering to you'
      assert_equal "[whispering] feri: whispering to you\n", recieve('geza')
      logout_2_users
   end

   def test_quit
      login_2_users
      say 'feri', '/quit'
      assert_equal "feri has disconnected\n", recieve('geza')
      logout 'geza'
   end

   def test_user_list
      login_2_users
      say 'feri', '/users'
      assert_equal "feri 127.0.0.1\ngeza 127.0.0.1\n", recieve('feri')
      logout_2_users
   end
end
