#!/usr/bin/env ruby
# coding: utf-8

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
		i2cset(0, 0b00000001)
		sleep 2.16e-3
	end

	def put_line(line, str)
		str.force_encoding(Encoding::BINARY)
		str.gsub!(/#{MAP.keys.join('|')}/, MAP)

		str = "%- 16s" % str

		# set ddram address
		i2cset(0, 0b10000000 + (0x40 * line))
		sleep 53e-6
		i2cset(*str.unpack("C*").map {|i| [0x80, i] }.flatten)
		sleep 53e-6
	end
end

class MPL115A2 < I2CDevice
	def initialize
		super(0x60)

		coefficient = i2cget(0x04, 8).unpack("n*")

		@a0  = fixed_point(coefficient[0], 12)
		@b1  = fixed_point(coefficient[1], 2)
		@b2  = fixed_point(coefficient[2], 1)
		@c12 = fixed_point(coefficient[3], 0) / (1<<9)
		p [@a0, @b1, @b2, @c12]
	end

	def fixed_point(fixed, int_bits)
		msb = 15
		deno = (1<<(msb-int_bits)).to_f
		if (fixed & (1<<15)).zero?
			fixed / deno
		else
			-( ( (~fixed & 0xffff) + 1) / deno )
		end
	end

	def calculate_hPa
		i2cset(0x12, 0x01) # CONVERT

		sleep 0.003

		data = i2cget(0x00, 4).unpack("n*")

		p_adc = (data[0]) >> 6
		t_adc = (data[1]) >> 6

		p_comp = @a0 + (@b1 + @c12 * t_adc) * p_adc + @b2 * t_adc
		hPa = p_comp * ( (1150 - 500) / 1023.0) + 500;
	end
end

avr = I2CDevice.new(0x65)
lcd = ACM1602NI.new

ws = WebSocket::Client::Simple.connect 'ws://localhost:51234'

ws.on :message do |msg|
	data = JSON.parse(msg.data)
	result =  data['result']
	lcd.put_line(1, "% 3s % 2sW %d" % [result['mode'], result['power'], result['frequency']])
end

ws.on :open do
	ws.send JSON.generate({"method"=>"status", "id" => "0"})
end

ws.on :close do |e|
	exit 1
end

loop do
	begin
		ant = avr.i2cget(0x00).unpack("c")[0].to_i
		lcd.put_line(0, "ANT:%d" % [ant])
		sleep 1
	rescue => e
		p e
		sleep 1
	end
end

