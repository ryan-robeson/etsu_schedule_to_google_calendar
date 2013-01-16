#!/usr/bin/env ruby

require 'bundler/setup'
require 'nokogiri'
require 'json'
require 'google/api_client'

class ETSUClass
  attr_accessor :number, :name, :start_date, :end_date, :days, :time, :room, :teacher

  # When class starts
  def start_time
    @time.gsub(/ /, "").split('-').first
  end

  # When class ends
  def end_time
    @time.gsub(/ /, "").split('-').last
  end

  # First day of class
  def start_date
    Date.strptime(@start_date, '%b %d, %Y')
  end
  
  # Last day of class
  def end_date
    Date.strptime(@end_date, '%b %d, %Y')
  end

  # Start of the class
  def formatted_start_time
    DateTime.strptime("#{start_date}T#{start_time}-05:00", '%Y-%m-%dT%I:%M%p%z')
  end

  # This is the end time of the class. Not the recurrence
  def formatted_end_time
    DateTime.strptime("#{start_date}T#{end_time}-05:00", '%Y-%m-%dT%I:%M%p%z')
  end

  # This is the time used for ending the recurrence
  def end_recurrence
    DateTime.strptime("#{end_date}T#{end_time}-05:00", '%Y-%m-%dT%I:%M%p%z')
  end

  def to_json(arg)
    {
      'number' => number,
      'name' => name,
      'start_date' => start_date,
      'end_date' => end_date,
      'start_time' => start_time,
      'formatted_start_time' => formatted_start_time,
      'end_time' => end_time,
      'formatted_end_time' => formatted_end_time,
      'days' => days,
      'time' => time,
      'room' => room,
      'teacher' => teacher
    }.to_json
  end
end

class Event
  def initialize(etsu_class)
    @ec = etsu_class
  end

  def summary
    "#{@ec.start_time} - #{@ec.name}"
  end

  def start_datetime
    @ec.formatted_start_time
  end

  def end_datetime
    @ec.formatted_end_time
  end

  def end_recurrence
    @ec.end_recurrence.new_offset(0).strftime("%Y%m%dT%H%M%SZ")
  end

  def description
    """#{@ec.number}
    #{@ec.name}
    #{@ec.room}
    #{@ec.teacher}"""
  end

  def recurrence
    [
      "RRULE:FREQ=WEEKLY;UNTIL=#{end_recurrence};WKST=SU;BYDAY=#{days.join(',')}"
    ]
  end

  def days
    days_map = {
      'M' => 'MO',
      'T' => 'TU',
      'W' => 'WE',
      'R' => 'TH',
      'F' => 'FR'
    }

    @ec.days.each_char.inject([]) do |a, c|
      a << days_map[c]
    end
  end

  def to_json(arg=nil)
    {
      'summary' => summary,
      'start' => {
        'dateTime' => start_datetime,
        'timeZone' => 'America/New_York'
      },
      'end' => {
        'dateTime' => end_datetime,
        'timeZone' => 'America/New_York'
      },
      'description' => description,
      'recurrence' => recurrence
    }.to_json
  end
end

doc = Nokogiri::HTML(ARGF.read)

rows = doc.css(".datadisplaytable")[1].css("tr")[1..5]

events = []

rows.each do |r|
  r = r.text.split("\n")

  c = ETSUClass.new
  c.number = r[1]
  c.name = r[2]
  c.start_date = r[6]
  c.end_date = r[7]
  c.days = r[8]
  c.time = r[9]
  c.room = r[10]
  c.teacher = r[11]
  
  events << Event.new(c)
end

oauth_yaml = YAML.load_file('.google-api.yaml')
client = Google::APIClient.new(application_name: 'etsu_schedule_to_calendar', application_version: 'v0.1')
client.authorization.client_id = oauth_yaml["client_id"]
client.authorization.client_secret = oauth_yaml["client_secret"]
client.authorization.scope = oauth_yaml["scope"]
client.authorization.refresh_token = oauth_yaml["refresh_token"]
client.authorization.access_token = oauth_yaml["access_token"]

if client.authorization.refresh_token && client.authorization.expired?
  client.authorization.fetch_access_token!
end

service = client.discovered_api('calendar', 'v3')

events.each do |event|
  result = client.execute(:api_method => service.events.insert,
                          :parameters => {'calendarId' => 'ftket4nt6b6h279jr00835vd50@group.calendar.google.com'},
                          :body => event.to_json,
                          :headers => {'Content-Type' => 'application/json'})
end

puts "Done."
