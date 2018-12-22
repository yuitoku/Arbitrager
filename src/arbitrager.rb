require "yaml"
require_relative "board_maker"
require_relative "position_maker"
require_relative "spread_analyzer"
require_relative "deal_maker"
require_relative "broker"

class Arbitrager
  def initialize
    @format = "%Y-%m-%d %H:%M:%S"
    @info = "INFO"
    @config = YAML.load_file("../config.yml")
  end

  def start
    output_info("Starting the serivce...")
    output_info("Starting Arbitrager...")
    output_info("Started Arbitrager.")
    output_info("Successfully started the service.")
    call_arbitrager
  end

  def stop
    output_info("Stopping Arbitrager...")
    output_info("Stopping the service...")
    output_info("Stopped Arbitrager.")
    output_info("Successfully stopped the service.")
    exit(0)
  end

  Signal.trap(:INT) do
    Arbitrager.new.stop
  end

  private

    def call_arbitrager
      threads = []
      @config[:brokers].map do |broker|
        threads << Thread.new do
          call_board_and_position_maker(broker)
        end
      end
      
      threads.each(&:join)
      output_position(@config[:brokers])
      analysis_result = call_spread_analyzer(@config)
      deal_result = call_deal_maker(@config, analysis_result)
      output_board(@config[:target_amount], analysis_result, deal_result[:message])
      #call_broker(@config, analysis_result) if deal_result[:reason] == "High profit"
      call_broker(@config, analysis_result)
    end

    def call_board_and_position_maker(broker)
      broker.merge!(BoardMaker.new.call_broker(broker))
      broker.merge!(PositionMaker.new.call_broker(broker))
    end

    def call_spread_analyzer(config)
      SpreadAnalyzer.new.analyze(config)
    end

    def call_deal_maker(config, analysis_result)
      DealMaker.new.decide(config, analysis_result)
    end

    def call_broker(config, a_result)
      output_info(">> Sending order targetting price #{a_result[:bid_broker]} Bid #{a_result[:best_bid]}")
      output_info(">> Sending order targetting price #{a_result[:ask_broker]} Bid #{a_result[:best_ask]}")    
      # steps in Nonce must be incremented by coincheck.
      sleep 1
      threads = []
      config[:brokers].each do |broker|
        threads << Thread.new do
          case broker[:broker]
          when a_result[:bid_broker]
            #Broker.new.order_market(broker, a_result[:best_ask], config[:target_amount], "buy")
            broker.merge!(Broker.new.order_market(broker, 100, config[:target_amount], "buy"))
          when a_result[:ask_broker]
            #Broker.new.order_market(broker, a_result[:best_bid], config[:target_amount], "sell")
            broker.merge!(Broker.new.order_market(broker, 10000000, config[:target_amount], "sell"))
          end
        end
      end

      threads.each(&:join)
      sleep 1
      check_order_status(config, a_result)
    end

    def check_order_status(config, a_result)
      threads = []
      p config
      config[:brokers].each do |broker|
        threads << Thread.new do
          broker.merge!(Broker.new.get_order_status(broker))
        end
      end

      threads.each(&:join)
    end

    def call_record_holder
    end

    def output_info(message)
      puts "#{Time.now.strftime(@format)} #{@info} #{message}"
    end

    def output_position(brokers)
      output_info("#{'POSITION'.center(50, '-')}")
      brokers.each do |broker|
        output_info("#{broker[:broker].ljust(10)} : #{broker[:position]} BTC") 
      end

      output_info("#{'-'.center(50, '-')}")
    end

    def output_board(target_amount, a_result, d_result)
      output_info("#{'ARBITRAGER'.center(50, '-')}")
      output_info("Looking for opportunity...")
      output_info("#{'Best bid'.ljust(18)} : #{a_result[:bid_broker].ljust(10)} Bid #{a_result[:best_bid]} #{a_result[:bid_amount]}")
      output_info("#{'Best ask'.ljust(18)} : #{a_result[:ask_broker].ljust(10)} Ask #{a_result[:best_ask]} #{a_result[:ask_amount]}")
      output_info("#{'Spread'.ljust(18)} : #{a_result[:spread]}")
      output_info("#{'Available amount'.ljust(18)} : #{a_result[:available_amount]}")
      output_info("#{'Target amount'.ljust(18)} : #{target_amount}")
      output_info("#{'Expected profit'.ljust(18)} : #{a_result[:profit]} (#{a_result[:profit_rate]}%)")
      output_info("#{d_result}")
    end
end

arbitrager = Arbitrager.new
arbitrager.start