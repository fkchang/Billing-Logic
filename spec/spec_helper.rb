require 'billing_logic'
# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# Require this file using `require "spec_helper.rb"` to ensure that it is only
# loaded once.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
  config.color_enabled = true
  config.formatter = 'documentation'
end

class MockProduct
  include BillingLogic::CommandBuilders::BuilderHelpers

  attr_accessor :id, :name, :price, :billing_cycle, :initial_payment
  def initialize(opts ={})
    opts.each do |k, v|
      self.send("#{k}=", v)
    end
  end

  def id
    "#{@id} @ $#{price}#{periodicity_abbrev(billing_cycle.period)}"
  end
end

class MockProfile
  attr_accessor :id, :products, :price, :next_payment_date, :billing_cycle, :active_or_pending
  def initialize(opts ={})
    opts.each do |k, v|
      self.send("#{k}=", v)
    end
  end

  def active_or_pending?
    active_or_pending
  end

  def refundable_payment_amount(foo)
    0.0
  end

end
