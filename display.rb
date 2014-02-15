#!/usr/bin/env ruby
# coding: utf-8
require 'rubygems'
require 'bundler'
Bundler.require

require 'websocket-client-simple'
require 'json'

class I2CDevice
	# ioctl command
	# Ref. https://www.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/include/linux/i2c.h
	I2C_RETRIES     = 0x0701
	I2C_TIMEOUT     = 0x0702
	I2C_SLAVE       = 0x0703
	I2C_SLAVE_FORCE = 0x0706
	I2C_TENBIT      = 0x0704
	I2C_FUNCS       = 0x0705
	I2C_RDWR        = 0x0707
	I2C_SMBUS       = 0x0720
	I2C_UDELAY      = 0x0705
	I2C_MDELAY      = 0x0706

	attr_accessor :address

	def initialize(address)
		@address = address
	end

	def i2cget(address, length=1)
		i2c = File.open("/dev/i2c-1", "r+")
		i2c.ioctl(I2C_SLAVE, @address)
		i2c.write(address.chr)
		ret = i2c.read(length)
		i2c.close
		ret
	end

	def i2cset(*data)
		i2c = File.open("/dev/i2c-1", "r+")
		i2c.ioctl(I2C_SLAVE, @address)
		i2c.write(data.pack("C*"))
		i2c.close
	end
end

class ACM1602NI < I2CDevice
	MAP = Hash[
		[
			"｡｢｣､・ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝﾞﾟ".split(//).map {|c|
				c.force_encoding(Encoding::BINARY)
			},
			(0xa1..0xdf).map {|c|
				c.chr
			}
		].transpose
	]

	def initialize
		super(0x50)
		@lines = []
		initialize_lcd
	end

	undef i2cget
	
	def initialize_lcd
		# function set
		i2cset(0, 0b00111100)
		sleep 53e-6
		# display on/off control
		i2cset(0, 0b00001100)
		sleep 53e-6
		clear
	end

	def clear
		@lines.clear
		i2cset(0, 0b00000001)
		sleep 2.16e-3
	end

	def put_line(line, str, force=false)
		str.force_encoding(Encoding::BINARY)
		str.gsub!(/#{MAP.keys.join('|')}/, MAP)

		str = "%- 16s" % str

		if force || str != @lines[line]
			# set ddram address
			i2cset(0, 0b10000000 + (0x40 * line))
			sleep 53e-6
			i2cset(*str.unpack("C*").map {|i| [0x80, i] }.flatten)
			sleep 53e-6
		end
		@lines[line] = str
	end

	# Usage:
	# lcd.define_character(0, [
	# 	0,1,1,1,0,
	# 	1,0,0,0,1,
	# 	1,1,0,1,1,
	# 	1,0,1,0,1,
	# 	1,1,0,1,1,
	# 	1,0,0,0,1,
	# 	1,0,0,0,1,
	# 	0,1,1,1,0,
	# ])
	def define_character(n, array)
		raise "n < 8" unless n < 8
		raise "array size must be 40 (5x8)" unless array.size == 40

		array = array.each_slice(5).map {|i|
			i.inject {|r,i| (r << 1) + i }
		}
		i2cset(0, 0b01000000 + (8 * n))
		sleep 53e-6
		i2cset(*array.map {|i| [0x80, i] }.flatten)
		sleep 53e-6
	end
end

lcd = ACM1602NI.new
result = {}

ws = WebSocket::Client::Simple.connect 'ws://localhost:51234'

ws.on :message do |msg|
	data   = JSON.parse(msg.data)
	result.merge!(data['result'])
end

ws.on :open do
	ws.send JSON.generate({"method"=>"status", "id" => "0"})
end

ws.on :close do |e|
	exit 1
end

loop do
	begin
		p result
		lcd.put_line(0, "% 3s % 2sW %d" % [result['mode'], result['power'], result['frequency']])
		lcd.put_line(1, "ANT:%s" % [ result['antenna.name'] ])
		sleep 0.5
	rescue => e
		p e
		sleep 1
	end
end

