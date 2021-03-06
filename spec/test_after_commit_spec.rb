require 'spec_helper'

describe TestAfterCommit do
  def rails4?
    ActiveRecord::VERSION::MAJOR >= 4
  end

  before do
    CarObserver.recording = false
    Car.called.clear
  end

  it "has a VERSION" do
    TestAfterCommit::VERSION.should =~ /^[\.\da-z]+$/
  end

  it "fires on create" do
    Car.create
    Car.called.should == [:create, :always]
  end

  it "fires on update" do
    car = Car.create
    Car.called.clear
    car.save!
    Car.called.should == [:update, :always]
  end

  it "fires on update_attribute" do
    car = Car.create
    Car.called.clear
    car.update_attribute :counter, 123
    Car.called.should == [:update, :always]
  end

  it "does not fire on rollback" do
    car = Car.new
    car.make_rollback = true
    car.save.should == nil
    Car.called.should == []
  end

  it "does not fire on ActiveRecord::RecordInvalid" do
    lambda {
      FuBear.create!
    }.should raise_exception(ActiveRecord::RecordInvalid)
    FuBear.called.should == []
  end

  it "does not fire multiple times in nested transactions" do
    Car.transaction do
      Car.transaction do
        Car.create!
        Car.called.should == []
      end
      Car.called.should == []
    end
    Car.called.should == [:create, :always]
  end

  it "fires when transaction block returns from method" do
    Car.returning_method_with_transaction
    Car.called.should == [:create, :always]
  end

  it "does not raises errors" do
    car = Car.new
    car.raise_error = true
    car.save!
  end

  it "can do 1 save in after_commit" do
    pending "different results than real" unless ENV['REAL']

    car = Car.new
    car.do_after_create_save = true
    car.save!

    expected = if rails4?
      [:save_once, :create, :always, :save_once, :always]
    else
      [:save_once, :create, :always, :save_once, :create, :always]
    end
    Car.called.should == expected
    car.counter.should == 3
  end

  it "returns on create and on create of associations" do
    Car.create!.class.should == Car
    Car.create!.cars.create.class.should == Car unless rails4?
  end

  it "returns on create and on create of associations without after_commit" do
    Bar.create!.class.should == Bar
    Bar.create!.bars.create.class.should == Bar unless rails4?
  end

  it "calls callbacks in correct order" do
    MultiBar.create!
    MultiBar.called.should == [:two, :one]
  end

  context "Observer" do
    before do
      CarObserver.recording = true
    end

    it "should record commits" do
      Car.transaction do
        Car.create
      end
      Car.called.should == [:observed_after_commit, :create, :always]
    end

    it "should record rollbacks caused by ActiveRecord::Rollback" do
      Car.transaction do
        car = Car.create
        raise ActiveRecord::Rollback
      end
      Car.called.should == [:observed_after_rollback]
    end

    it "should record rollbacks caused by any type of exception" do
      begin
        Car.transaction do
          car = Car.create
          raise Exception, 'simulated error'
        end
      rescue Exception => e
        e.message.should == 'simulated error'
      end
      Car.called.should == [:observed_after_rollback]
    end
  end

  context "nested after_commit" do
    it 'is executed' do
      skip if ENV["REAL"] && ActiveRecord::VERSION::MAJOR == 4 # infinite loop
      pending if !ENV["REAL"]

      @address = Address.create!
      lambda {
        Person.create!(:address => @address)
      }.should change(@address, :number_of_residents).by(1)

      # one from the line above and two from the after_commit
      @address.people.count.should == 3

      @address.number_of_residents.should == 3
    end
  end
end
