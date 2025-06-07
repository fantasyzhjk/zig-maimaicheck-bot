#!/usr/bin/env ruby

require 'websocket-client-simple'
require 'json'
require 'thread'

def safe_decode(data)
  if data.encoding == Encoding::BINARY
    # 如果是二进制数据，假设是UTF-8
    data.force_encoding('UTF-8')
  elsif data.valid_encoding?
    # 如果编码有效，直接使用
    data
  else
    # 如果编码无效，安全转换
    data.encode('UTF-8', invalid: :replace, undef: :replace)
  end
end

class WebSocketClient
  def initialize(url)
    @url = url
    @ws = nil
    $running = false
  end

  def connect
    puts "正在连接到 #{@url}..."
    
    @ws = WebSocket::Client::Simple.connect @url
    
    @ws.on :open do |event|
      puts "WebSocket 连接已建立"
      $running = true
    end

    @ws.on :message do |event|
      msg = JSON.parse(safe_decode(event.data))
      
      puts "收到消息: #{msg}"
    end

    @ws.on :error do |event|
      puts "WebSocket 错误: #{event.data}"
    end

    @ws.on :close do |event|
      puts "WebSocket 连接已关闭"
      $running = false
    end

    # 等待连接建立
    sleep 0.1 until $running
  end

  def send_message(message)
    if @ws && $running
      # json_message = {
      #   "type" => "user_input",
      #   "timestamp" => Time.now.to_f,
      #   "message" => message,
      # }

      json_message = {
        time: Time.now.to_i,
        self_id: 1234567890,
        post_type: "message",
        message_type: "private",
        sub_type: "friend",
        message_id: 112233,
        user_id: 9876543210,
        message: [
          # 假设消息是 CQ码或结构化消息，这里用示例结构表示
          { type: "text", data: { text: message } }
        ],
        raw_message: message,
        font: 123,
        sender: {
          user_id: 9876543210,
          nickname: "小明",
          sex: "male",
          age: 18
        }
      }
      
      puts "发送消息: #{json_message}"
      @ws.send(json_message.to_json)
    else
      puts "WebSocket 未连接"
    end
  end

  def start_input_loop
    puts "\n请输入消息 (输入 'quit' 或 'exit' 退出):"
    
    input_thread = Thread.new do
      loop do
        print "> "
        input = gets.chomp
        
        case input.downcase
        when 'quit', 'exit'
          puts "正在退出..."
          @ws.close if @ws
          break
        when 'ping'
          send_ping
        when ''
          # 忽略空输入
        else
          send_message(input)
        end
      end
    end

    input_thread.join
  end

  def send_ping
    if @ws && $running
      ping_message = {
        "type" => "ping",
        "timestamp" => Time.now.to_f,
      }
      
      puts "发送消息: #{ping_message}"
      @ws.send(ping_message.to_json)
    end
  end

  def close
    @ws.close if @ws
    $running = false
  end
end

# 使用示例
if __FILE__ == $0
  # 默认连接到本地WebSocket服务器
  # 你可以修改这个URL来连接到其他服务器
  url = ARGV[0] || "ws://localhost:9224"
  
  begin
    client = WebSocketClient.new(url)
    client.connect
    client.start_input_loop
  rescue Interrupt
    puts "\n收到中断信号，正在关闭..."
  rescue StandardError => e
    puts "错误: #{e.message}"
  ensure
    client&.close
  end
end