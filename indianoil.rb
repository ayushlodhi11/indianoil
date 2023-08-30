
require 'json'
# require 'selenium-webdriver'
require 'watir'
require 'nokogiri'
require 'byebug'
require "open-uri"

browser_switches = [
  '--disable-gpu',
  '--accept-encoding=gzip, deflate', '--disable-logging', '--blink-settings=imagesEnabled=false',
  '--accept-language=en-GB,en;q=0.9,en-US;q=0.8,hi;q=0.7,la;q=0.6',
  '--connection=keep-alive', '--enable-features=NetworkService,NetworkServiceInProcess', '--dnt=1',
  '--disable-blink-features', '--disable-crash-reporter', '--disable-breakpad', '--no-sandbox',
  '--hide-scrollbars', '--disable-extensions', '--disable-dev-shm-usage',
  '--disable-hang-monitor', '--disable-web-security', '--disable-session-crashed-bubble', '--disable-background-networking',
  '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-sync',
  '--log-level=0', '--v=99', '--ignore-certificate-errors',
  '--disable-blink-features=AutomationControlled', # disable flag for webdriver
  # '--disable-features=UserAgentClientHint', # remove sec-ch-* frim chrome https://www.chromium.org/updates/ua-ch/
]
raw_data = {}
File.read('app/services/utils/ini.txt').split("\n").map{|a| a.split("\t")}.select{|a| a[0].to_s.strip.length >0 }.map {|a| raw_data[a[0]] = a}
all_data = (JSON.parse(File.read('app/services/utils/all_data.json')) rescue {})
running_data = (JSON.parse(File.read('app/services/utils/running_data.json')) rescue {})

(all_data.keys + raw_data.keys).each do |k|
  # all_data[k] = raw_data[k] if !all_data[k] && raw_data[k]
  all_data[k] = running_data[k] if running_data[k]
end

transaction = (JSON.parse(File.read('app/services/utils/transaction.json')) rescue {})


def get_data(browser)
  data={}
  browser.wait_until(timeout: 4) { browser.element(xpath: '//*[@id="1_s_1_l_EPIC_Relationship_Integration_Id"]/a').exist? }
  data[:rid] = browser.element(xpath: '//*[@id="1_s_1_l_EPIC_Relationship_Integration_Id"]/a').text.to_s.strip
  data[:type] = browser.element(xpath: '//*[@id="1_s_1_l_Urban_Rural_Type"]').text.to_s.strip
  data[:lbody] = browser.element(xpath: '//*[@id="1_s_1_l_Local_Body"]').text.to_s.strip
  data
end
loop do
  browser = nil
  (all_data.keys).each do |k|
    all_data[k] = running_data[k] if running_data[k]
  end
  File.open('app/services/utils/all_data.json', 'wb') {|f| f.write all_data.to_json}
  running_data = all_data.select {|a,b| b[3] != "DONE" && b[3] != 'MISSING'}.to_a[0..100].to_h 
  File.open('app/services/utils/running_data.json', 'wb') {|f| f.write running_data.to_json}
  tid = Time.now.to_i
  rid = ''
  transaction[tid] = []
  exit if running_data.keys.count == 0
  running_data = JSON.parse(File.read('app/services/utils/running_data.json')).select {|a,b| b[3] != "DONE" && b[3] != 'MISSING'}.to_h 
  puts "[#{Time.now}][#{tid}] Starting loop; Total jobs #{running_data.keys.count}"
  # data[:rid] = "7000000064641715"
  # data[:type] = "Urban"
  # data[:lbody] = "Sarila"
  Selenium::WebDriver::Chrome.path = "/Users/Ghost/Startup/aws/Chrome/81/Google Chrome.app/Contents/MacOS/Google Chrome"
  Selenium::WebDriver::Chrome::Service.driver_path = "/Users/Ghost/Startup/aws/Chrome/81/chromedriver"
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome("goog:chromeOptions" => {"args" => browser_switches})
  # @capabilities = Selenium::WebDriver::Remote::Capabilities.chrome()
  browser = Watir::Browser.new(:chrome, capabilities: capabilities)
  # browser = Watir::Browser.new(:chrome)
  browser.goto('https://sdms.px.indianoil.in/edealer_enu/start.swe?SWECmd=Start&SWEHo=sdms.px.indianoil.in')
  Watir::Wait.until(:timeout => 15){ browser.element(xpath: '//*[@id="loginData"]/div/div[1]/label').exist? }
  browser.text_field(id: "username").set("0000156204_01")
  browser.text_field(id: "password").set("Indane12!12")
  browser.button(id: "submitid").click
  sleep(5)

  browser.goto('https://sdms.px.indianoil.in/edealer_enu/start.swe?SWECmd=GotoView&SWEView=EPIC+Relationship+LGD+Address+Compliance+View&SWERF=1')
  sleep(1)

  Watir::Wait.until(:timeout => 15){browser.element(id: "jqgh_s_1_l_EPIC_Relationship_Integration_Id").exists?}
  running_data.values.each do |rid, type, lbody|
    data = {rid: rid, type: type, lbody: lbody}
    puts "[#{Time.now}][#{tid}] STARTING JOB: #{rid}"
    @retry = 2
    missing = false
    begin 
      browser.element(xpath: '//*[@id="s_S_A1_div"]/form/span/div/div[2]/div[2]/input[2]').set(data[:rid])
      browser.button(xpath: '//*[@id="s_1_1_0_0_Ctrl"]').click
      sleep(0.5)
      Watir::Wait.until(:timeout => 2) { browser.element(xpath: '//*[@id="1_s_1_l_Urban_Rural_Type"]').exist? }
      ldata = get_data(browser)
    rescue => error
      sleep(1)
      puts "[#{Time.now}][#{tid}] RETRYING JOB: #{rid}"
      @retry -= 1
      retry if @retry >= 0
      missing = true
    end
    puts "[#{Time.now}][#{tid}] GETTING DATA: #{rid}"
    status = 'MISSING'
    if !missing
      ldata = get_data(browser)

      if ldata[:rid].length > 0 && ldata[:rid] == data[:rid]
        if ldata[:type] != data[:type]
          browser.element(xpath: '//*[@id="1_s_1_l_Urban_Rural_Type"]').click
          sleep(0.1)
          browser.element(xpath: '//*[@id="1_Urban_Rural_Type"]').set(type)
          sleep(0.1)
        end
        if ldata[:lbody] != data[:lbody]
          browser.element(xpath: '//*[@id="1_s_1_l_Local_Body"]').click
          sleep(0.1)
          browser.element(xpath: '//*[@id="1_Local_Body"]').set(lbody)
          sleep(0.1)
        end
        if ldata[:type] != data[:type] || ldata[:lbody] != data[:lbody]
          browser.button(xpath: '//*[@id="s_1_1_0_0_Ctrl"]').click
          sleep(0.2)
          puts "[#{Time.now}][#{tid}] SUBMITTING DATA: #{rid}"
          ldata = get_data(browser)
        end
      end
      status = 'INVALID'
      if running_data[rid][0..2] == ldata.values
        status = 'DONE'
      end
    end
    running_data[rid][3] = status
    File.open('app/services/utils/running_data.json', 'wb') {|f| f.write running_data.to_json}
    transaction[tid] << [data, ldata]
    puts "[#{Time.now}][#{tid}] FINISED JOB: #{rid} with status #{status}"
  end
rescue => error
    puts "[#{Time.now}][#{tid}] ERROR JOB: #{rid}"
    p error
ensure
  if browser
    begin
      Timeout.timeout(2) { browser.element(xpath: '//*[@id="tb_0"]').click }
      Timeout.timeout(5) { browser.element(xpath: '//*[@id="tb_item_4"]/button').click }
    rescue => error
      p "error on logout"
      p error
      sleep(2)
    ensure
      browser.close rescue nil
    end
    File.open('app/services/utils/transaction.json', 'wb') {|f| f.write transaction.to_json}
  end
end
