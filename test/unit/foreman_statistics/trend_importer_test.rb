require 'test_statistics_helper'

module ForemanStatistics
  class TrendImporterTest < ActiveSupport::TestCase
    setup do
      TrendCounter.unscoped.delete_all
      Trend.unscoped.delete_all
    end

    test 'counts Puppet environments through host facets, including empty environments' do
      skip 'Puppet plugin is not installed' unless defined?(ForemanPuppet::Environment)

      as_admin do
        populated = FactoryBot.create(:environment)
        other = FactoryBot.create(:environment)
        empty = FactoryBot.create(:environment)
        FactoryBot.create_list(:host, 2, :with_puppet_enc, :environment => populated)
        FactoryBot.create(:host, :with_puppet_enc, :environment => other)
        FactoryBot.create(:host)
        create_environment_trend

        TrendImporter.update!

        assert_equal 2, environment_value(populated).trend_counters.last.count
        assert_equal 1, environment_value(other).trend_counters.last.count
        assert_equal 0, environment_value(empty).trend_counters.last.count
      end
    end

    test 'preserves environment counter history and extends unchanged intervals' do
      skip 'Puppet plugin is not installed' unless defined?(ForemanPuppet::Environment)

      as_admin do
        original = FactoryBot.create(:environment)
        replacement = FactoryBot.create(:environment)
        host = FactoryBot.create(:host, :with_puppet_enc, :environment => original)
        create_environment_trend
        first_time = Time.current.change(:usec => 0)

        travel_to(first_time) { TrendImporter.update! }
        original_value = environment_value(original)
        first_counter = original_value.trend_counters.last

        travel_to(first_time + 30.minutes) { TrendImporter.update! }
        assert_equal [first_counter.id], original_value.trend_counters.pluck(:id)
        assert_equal first_time + 30.minutes, first_counter.reload.interval_end

        host.puppet.update!(:environment => replacement)
        travel_to(first_time + 60.minutes) { TrendImporter.update! }
        assert_equal [1, 0], original_value.trend_counters.pluck(:count)
        assert_equal first_time + 60.minutes, first_counter.reload.interval_end
        assert_equal [0, 1], environment_value(replacement).trend_counters.pluck(:count)
      end
    end

    test 'continues counting operating systems and facts without Puppet trends' do
      as_admin do
        os = FactoryBot.create(:operatingsystem)
        host = FactoryBot.create(:host, :operatingsystem => os)
        fact_name = FactoryBot.create(:fact_name)
        FactoryBot.create(:fact_value, :host => host, :fact_name => fact_name, :value => 'present')
        FactoryBot.create(:foreman_statistics_trend_os, :trendable_id => nil)
        FactoryBot.create(:foreman_statistics_fact_trend, :trendable => fact_name)

        TrendImporter.update!

        os_value = ForemanTrend.has_value.find_by!(:trendable_type => 'Operatingsystem', :trendable_id => os.id)
        fact_value = FactTrend.has_value.find_by!(:trendable_id => fact_name.id, :fact_value => 'present')
        assert_equal 1, os_value.trend_counters.last.count
        assert_equal 1, fact_value.trend_counters.last.count
      end
    end

    private

    def create_environment_trend
      FactoryBot.create(:foreman_statistics_foreman_trend,
        :trendable_type => 'ForemanPuppet::Environment', :trendable_id => nil)
    end

    def environment_value(environment)
      ForemanTrend.has_value.find_by!(:trendable_type => 'ForemanPuppet::Environment', :trendable_id => environment.id)
    end
  end
end
