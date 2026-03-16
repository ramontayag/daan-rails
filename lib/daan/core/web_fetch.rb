require 'selenium-webdriver'

module Daan
  module Core
    class WebFetch < RubyLLM::Tool
      description "Fetch web content using browser automation (handles JavaScript like normal browsing)"
      param :url, desc: "URL to fetch"
      param :timeout, desc: "Timeout in seconds (default: 10)", required: false
      param :wait_for_selector, desc: "CSS selector to wait for before returning content (optional)", required: false

      def initialize(workspace: nil, chat: nil)
        @workspace = workspace
        @chat = chat
      end

      def execute(url:, timeout: 10, wait_for_selector: nil)
        validate_url(url)
        
        driver = nil
        begin
          driver = create_driver(timeout)
          driver.navigate.to(url)
          
          if wait_for_selector
            wait_for_element(driver, wait_for_selector, timeout)
          else
            # Default wait for basic page load and JavaScript execution
            sleep(2)
          end
          
          driver.page_source
        rescue Selenium::WebDriver::Error::TimeoutError => e
          raise "Page load timeout after #{timeout}s for #{url}: #{e.message}"
        rescue Selenium::WebDriver::Error::WebDriverError => e
          raise "WebDriver error: #{e.message}"
        rescue StandardError => e
          raise "Failed to fetch #{url}: #{e.message}"
        ensure
          driver&.quit
        end
      end

      private

      def validate_url(url)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise ArgumentError, "Invalid URL: #{url}. Must be HTTP or HTTPS."
        end
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid URL format: #{url}"
      end

      def create_driver(timeout)
        options = Selenium::WebDriver::Chrome::Options.new
        
        # Basic headless configuration
        options.add_argument('--headless')
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        options.add_argument('--disable-gpu')
        
        # Additional stability options
        options.add_argument('--disable-extensions')
        options.add_argument('--disable-background-timer-throttling')
        options.add_argument('--disable-backgrounding-occluded-windows')
        options.add_argument('--disable-renderer-backgrounding')
        
        # Set window size for consistent rendering
        options.add_argument('--window-size=1400,900')
        
        # Create driver instance
        driver = Selenium::WebDriver.for(:chrome, options: options)
        
        # Set timeouts
        driver.manage.timeouts.page_load = timeout
        driver.manage.timeouts.script_timeout = timeout
        driver.manage.timeouts.implicit_wait = 5
        
        driver
      end

      def wait_for_element(driver, selector, timeout)
        wait = Selenium::WebDriver::Wait.new(timeout: timeout)
        wait.until { driver.find_element(:css, selector) }
      rescue Selenium::WebDriver::Error::TimeoutError
        raise "Timeout waiting for selector '#{selector}' after #{timeout}s"
      rescue Selenium::WebDriver::Error::NoSuchElementError
        raise "Element not found: #{selector}"
      end
    end
  end
end