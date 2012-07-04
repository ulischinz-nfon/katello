#
# Copyright 2012 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

#
# Please note this module is required either from Rails and from Puppet.
#
module Util
  module Puppet
    config_paths = []
    default_path = '/usr/share/katello/install/default-answer-file'
    if File.file?(default_path)
      config_paths.push(default_path)
    end
    if ENV['KATELLO_ANSWER_FILE'] and File.file?(ENV['KATELLO_ANSWER_FILE'])
      config_paths.push(ENV['KATELLO_ANSWER_FILE'])
    end
    @config_values = {}
    config_paths.each do |filename|
      file = File.new(filename, "r")
      while (line = file.gets)
        if line =~ /^\s*#/
          next
        end
        line = line.gsub(/\s+$/, '')
        if not line =~ /\S+/
          next
        end
        if line =~ /^\s*(\w+)\s*=\s*(.*)/
          @config_values[$1] = $2
        else
          puts "Unsupported config line #{line} in file #{filename}"
        end
      end
      file.close
    end

    def self.config_value(name)
      return @config_values[name]
    end
  end
end
