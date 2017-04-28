# frozen_string_literal: true
require 'tempfile'

class MigrationRebaser
  def migrate_migrations
    return 0 if migrations.empty?

    begin
      move_migrations
      File.open(schema_path,'r') do |file|
        file.each_line do |line|
          process_line(file, line)
        end
      end

      temp_file.flush
      temp_file.close(false)
      FileUtils.mv(temp_file.path, schema_path)
    ensure
      temp_file.unlink
    end
    migrations.count
  end

  private

  def schema_path; "#{Dir.pwd}/db/schema.rb" end
  def temp_file; @temp_file ||= Tempfile.new('schema.rb') end
  def schema_date; Time.now.strftime('%Y%m%d%H%M%S') end
  def git_status; @git_status ||= `git status -s db/migrate/` end
  def processed_schema_conflict?; !!@processed_schema_conflict end

  def process_line(file, line)
    if line[/<<<<<<</] && !processed_schema_conflict?
      cut_schema(file)
      temp_file.puts "ActiveRecord::Schema.define(version: #{@new_date}) do"
      @processed_schema_conflict = true
    else
      temp_file.write line
    end
  end

  def cut_schema(file)
    file.each_line do |line|
      return line if line[/>>>>>>>/]
    end
  end

  def migrations
    @migrations ||= set_migrations
  end

  def set_migrations
    migrations = []
    StringIO.new(git_status).each_line do |line|
      if line[/db\/migrate/]
        migrations << line.chomp.split.last
      end
    end
    migrations
  end

  def move_migration(migration, date)
    new_migration = migration.gsub(/(\d+)/, date)
    FileUtils.mv("#{Dir.pwd}/#{migration}","#{Dir.pwd}/#{new_migration}")
  end

  def move_migrations
    new_date = ''
    last_date = ''
    migrations.each do |migration|
      while(last_date == (new_date = schema_date)) do
        sleep 0.2
        new_date = schema_date
      end
      move_migration(migration, new_date)
      last_date = new_date
    end
    @new_date = last_date
  end
end

puts "Migrated #{MigrationRebaser.new.migrate_migrations} migrations"
