require "socket"

class YourRedisServer
  def initialize(port)
    @server = TCPServer.new(port)
    @clients = []
  end

  def listen
    loop do
      fds_to_watch = [@server, *@clients]
      ready_to_read, _, _ = IO.select(fds_to_watch)
      ready_to_read.each do |fd|
        case fd
        when @server
          @clients << @server.accept
        else
          handle_client(fd)
        end
      end
    end
  end

  def handle_client(client)
    line = client.readpartial(1024)
    commands = line.split
    commands.each do |command|
      case command
      when "ping"
        client.write("+PONG\r\n")
        else
        client.write("-ERR unknown command '#{command}'\r\n")
        @clients.delete(client)
        client.close
      end
    end
  end
end

YourRedisServer.new(6379).listen
