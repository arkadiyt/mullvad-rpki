require 'bundler/setup'

require 'csv'
require 'json'
require 'net/https'
require 'pry-byebug'
require 'timeout'

def execute(args)
  IO.popen(['mullvad'] + args).read
end

def test_relay(country, city, hostname)
  puts "Testing #{hostname}"

  Timeout.timeout(10) do
    if hostname.index('wireguard') == nil
      execute(%w{relay set tunnel-protocol any})
    else
      execute(%w{relay set tunnel-protocol wireguard})
    end
    execute(%w{relay set location} + [country, city, hostname])

    # Block until connection is successful
    until execute(%w{status}).index('Connected to') != nil
      sleep 0.5
    end
    # Connected to exit now

    valid = ::JSON.parse(::Net::HTTP.get(URI('https://valid.rpki.cloudflare.com/')))
    invalid = ::Net::HTTP.get(URI('https://invalid.rpki.cloudflare.com/'))
    ip = ::Net::HTTP.get(URI('https://bot.whatismyipaddress.com'))

    puts "  IP address: #{ip}"
    puts "  #{valid}"
    puts "  #{invalid}"

    [hostname, ip, valid['asn'], valid['name'], valid['status'] == 'valid', invalid != 'invalid']
  end
rescue StandardError => ex
  # Should get here if invalid.rpki.cloudflare.com is unroutable
  puts "Got exception #{ex}"
end

def parse_relays
  current_country = nil
  current_city = nil
  relays = []

  execute(%w{relay list}).lines.each do |line|
    line = line.strip
    next if line.empty?

    match = line.match(/\A.*\((\w\w)\)\z/)
    if match
      current_country = match[1]
      next
    end

    match = line.match(/\A.+ \((\w{3})\).*\z/)
    if match
      current_city = match[1]
      next
    end

    match = line.match(/\A(.+) \(\d{0,3}.\d{0,3}.\d{0,3}.\d{0,3}\).*\z/)
    relays << [current_country, current_city, match[1]]
  end

  relays
end

def main(args)
  relays = parse_relays

  CSV.open('results.csv', 'r+', headers: %w{relay ip asn name valid invalid}, write_headers: true) do |csv|
    tested = csv.map do |row|
      [row['relay'], true]
    end.to_h

    relays.each do |country, city, hostname|
      next if tested[hostname]

      sleep 2 # Work around a mullvad race condition
      result = test_relay(country, city, hostname)
      if result
        csv << result
        csv.flush
      else
        puts "Couldn't test #{hostname}"
      end
    end
  end
end

main(ARGV) if $0 == __FILE__
