require 'spec_helper'

module BillingLogic

  # an IndependentPaymentStrategy gives each product its own payment_profile
  describe Strategies::IndependentPaymentStrategy do
    module With0RefundablePayment
      def refundable_payment_amount(foo)
        0.0
      end
    end
    let(:monthly_cycle) do
      BillingCycle.new(:period => :month,
                       :frequency => 1,
                       :anniversary => Date.current - 7)
    end

    let(:yearly_cycle) do
      BillingCycle.new(:period => :year,
                       :frequency => 1,
                       :anniversary => Date.current - 7)
    end

    let(:product_a) { MockProduct.new(:identifier => 1, :name => 'A', :price => 10, :billing_cycle => monthly_cycle, :initial_payment => 0.0) }
    let(:product_a_yearly) { MockProduct.new(:identifier => 1, :name => 'A', :price => 90, :billing_cycle => yearly_cycle, :initial_payment => 0.0) }
    let(:product_b) { MockProduct.new(:identifier => 2, :name => 'B', :price => 20, :billing_cycle => monthly_cycle, :initial_payment => 0.0) }
    let(:product_c) { MockProduct.new(:identifier => 3, :name => 'C', :price => 30, :billing_cycle => monthly_cycle, :initial_payment => 0.0) }
    let(:product_d) { MockProduct.new(:identifier => 4, :name => 'D', :price => 40, :billing_cycle => monthly_cycle, :initial_payment => 0.0) }
    let(:strategy)  { Strategies::IndependentPaymentStrategy.new(:current_state => ::BillingLogic::CurrentState.new([])) }


    let(:profile_a) do
      MockProfile.new(
            :products =>          [product_a, product_b],
            :current_products =>  [product_a, product_b],
            :active_products =>   [product_a, product_b],
            :price => 30,
            :identifier => 'i-1',
            :paid_until_date => monthly_cycle.next_payment_date,
            :active_or_pending => true
           )
    end

    let(:canceled_profile_d) do
      MockProfile.new(
                     :products => [product_d],
                     :current_products => [product_d],
                     :active_products => [],
                     :price => 40,
                     :identifier => 'i-4',
                     :paid_until_date => monthly_cycle.next_payment_date,
                     :active_or_pending => false,
                    )
    end

    let(:strategy_with_3_active_products) do
      profile = MockProfile.new(
                     :products => [product_c],
                     :current_products => [product_c],
                     :active_products => [product_c],
                     :price => 30,
                     :identifier => 'i-2',
                     :paid_until_date => monthly_cycle.next_payment_date,
                     :active_or_pending => true,
                     )
      Strategies::IndependentPaymentStrategy.new(:current_state => ::BillingLogic::CurrentState.new([profile_a, profile]))
    end

    describe "#active_products" do
      it "should return an array" do
        strategy.active_products.should be_kind_of(Array)
      end

      it "should return the products in the current state" do
        strategy_with_3_active_products.active_products.should == [product_a, product_b, product_c]
      end
    end

    describe "#products_to_be_added" do
      it "should not return products that are already in the current state" do
        strategy.current_state = ::BillingLogic::CurrentState.new([])
        strategy.desired_state = []
        strategy.products_to_be_added.should be_empty
      end

      it "should return products that are not in the current state" do
        strategy.current_state = ::BillingLogic::CurrentState.new([])
        strategy.desired_state = [product_a]
        strategy.products_to_be_added.should == [product_a]
      end
    end

    describe "#products_to_be_added_grouped_by_date" do
      it "should return products that are not in the current state" do
        strategy.current_state = ::BillingLogic::CurrentState.new([])
        strategy.desired_state = [product_a]
        strategy.products_to_be_added_grouped_by_date.should == [[[product_a], Date.current]]
      end
    end

    context 'with empty current state' do
      let(:strategy) { Strategies::IndependentPaymentStrategy.new(:current_state => ::BillingLogic::CurrentState.new([])) }

      context 'with an empty desired state' do
        it 'should return an empty command list' do
          strategy.command_list.should == []
        end
      end

      context 'with 1 new subscription in the desired state' do
        before do
          strategy.desired_state = [product_a]
        end

        it "should call create_recurring_payment_command with 1 product on the command builder object" do
          strategy.payment_command_builder_class.should_receive(:create_recurring_payment_commands).with([product_a], :paid_until_date => Date.current).once
          strategy.command_list
        end

        it 'should return 1 command in the command list' do
          strategy.command_list.size.should == 1
        end

      end

    end

    context 'with 2 current profile with 3 products' do
      context "when going towards a desired state of no products" do
        before do
          strategy_with_3_active_products.desired_state = []
        end

        # NOTE: this should be moved to a separate class
        it 'should know which product should be removed' do
          strategy_with_3_active_products.products_to_be_removed.should == [product_a, product_b, product_c]
        end

        it "should call :cancel_recurring_payment_command twice" do
          strategy_with_3_active_products.should_receive(:cancel_recurring_payment_command).twice
          strategy_with_3_active_products.command_list
        end
      end

      context "when removing a partial product from a profile" do
        before do
          strategy_with_3_active_products.desired_state = [product_b, product_c]
        end

        it "should remove the product from the profile with the partial match" do
          strategy_with_3_active_products.should_receive(:remove_product_from_payment_profile).with('i-1', [product_a], {}).once
          strategy_with_3_active_products.command_list
        end

      end

      context "with a yearly subscription" do
        before do
          profile_a.products          = [product_a_yearly]
          profile_a.active_products   = profile_a.products
          profile_a.current_products  = profile_a.products
          profile_a.paid_until_date   = product_a_yearly.billing_cycle.next_payment_date
          profile_a.billing_cycle     = yearly_cycle
          strategy.current_state      = ::BillingLogic::CurrentState.new([profile_a])
        end

        it "should add monthly plan at the end of the year when switching to monthly cycle" do
          strategy.desired_state = [product_a]
          strategy.should_receive(:create_recurring_payment_command).with([product_a], hash_including(:paid_until_date => profile_a.paid_until_date)).once
          strategy.should_receive(:cancel_recurring_payment_command).with(profile_a, {}).once
          strategy.command_list
          # Note: I used the following for debugging, but leaving it inside
          # would couple the tests for the strategy with the command builder as
          # well, which would be bad.
          # .should == ["add 1 @ $10/mo on #{profile_a.next_payment_date.strftime('%m/%d/%y')}", "cancel i-1 now"]
        end

        context "that is cancelled and being re-added" do
          before do
            profile_a.active_or_pending = false
            profile_a.active_products = []
            profile_a.current_products = []
            strategy.desired_state = [product_a]
          end

          it "shouldn't try to cancel the yearly subscription if already cancelled" do
            strategy.should_not_receive(:cancel_recurring_payment_command)
            strategy.command_list
          end

          it "should re-add the cancelled product at the end of the year" do
            strategy.should_receive(:create_recurring_payment_command).with([product_a], :paid_until_date => profile_a.paid_until_date).once
            strategy.command_list
          end
        end
      end

      context "with one of them cancelled" do
        before do
          state = ::BillingLogic::CurrentState.new([canceled_profile_d])
          strategy.current_state = state
        end
        context "when re-adding the cancelled product" do
          it "should add it to the end of the cancelled period" do
            strategy.desired_state = [product_d]
            strategy.should_receive(:create_recurring_payment_command).with([product_d], :paid_until_date => canceled_profile_d.paid_until_date).once
            strategy.command_list
          end
        end

      end

      context "with one of them cancelled twice" do
        before do
          state = ::BillingLogic::CurrentState.new([canceled_profile_d, canceled_profile_d.clone])
          strategy.current_state = state
        end

        context "when re-adding the cancelled product" do
          it "should add it to the end of the cancelled period" do
            strategy.desired_state = [product_d]
            strategy.should_receive(:create_recurring_payment_command).with([product_d], :paid_until_date => canceled_profile_d.paid_until_date).once
            strategy.command_list
          end
        end

      end

    end
  end
end
