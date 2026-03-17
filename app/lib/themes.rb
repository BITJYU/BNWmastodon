# frozen_string_literal: true

require 'singleton'
require 'yaml'

class Themes
  include Singleton

  HIDDEN_NAMES = %w(default theme-ui-dark).freeze

  def initialize
    @conf = YAML.load_file(Rails.root.join('config', 'themes.yml'))
  end

  def names
    @conf.keys - HIDDEN_NAMES
  end
end
