#!/usr/bin/env ruby
# coding: utf-8
require 'rubygems'
require 'bundler'
Bundler.require

require 'websocket-client-simple'
require 'json'
require "i2c"
require "i2c/device/acm1602ni"

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

