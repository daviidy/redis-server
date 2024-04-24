require "socket"

class YourRedisServer
  def initialize(port)
    @server = TCPServer.new(port)
    @clients = []
  end

  def start
    loop do
      fds_to_watch = [@server, *@clients]
      ready_to_read, _, _ = IO.select(fds_to_watch)
      ready_to_read.each do |fd|
        case fd
        when @server
          accept_client
        else
          p "client fd = #{fd}"
          handle_client(fd)
        end
      end
    end
  end

  def accept_client
    @clients << @server.accept
  end

  def handle_client(client)
    puts 'client request = ' + client.gets
    client.write("+PONG\r\n") if client.gets === "ping"
  end
end

YourRedisServer.new(6379).start
