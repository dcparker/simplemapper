require File.expand_path(File.dirname(__FILE__) + '/../../../lib/simple_mapper/default_plugins/associations')

class String
  def self.random(len=nil)
    len = rand(24) unless len
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['-', '_']
    newpass = ''
    1.upto(len) { |i| newpass << chars[rand(chars.size-1)] }
    newpass
  end
end

class Human
  class << self
    def all(finder_options={})
      conditions_proc = finder_options.delete(:conditions)
      # puts "FINDER OPTIONS: #{finder_options.inspect}"
      # puts "CONDITIONS: #{conditions_proc}"
      loaded_objs.reject do |o|
        !((conditions_proc.is_a?(Proc) ? conditions_proc.call(o) : true) && finder_options.all? {|k,v| (o.respond_to?(k) ? o.send(k) : k) == v})
      end
    end

    def loaded_objs
      @loaded_objs ||= []
    end

    def new(*args)
      obj = allocate
      loaded_objs << obj
      obj.send(:initialize, *args)
      obj
    end

    def key
      :id
    end
  end

  include SimpleMapper::Associations

  attr_reader :id

  attr_accessor :gender, :name

  def initialize(attributes={})
    attributes.each {|k,v| instance_variable_set("@#{k}", v)}
  end

  def inspect
    "#<#{self.class.name}:#{self.object_id} #{[(@association_sets || []).collect {|k,v| k.inspect+'('+(v.is_a?(Enumerable) ? v : [v]).length.to_s+')'}, [:gender].reject {|p| self.send(p).nil?}.map {|p| ":#{p} => #{self.send(p)}"}].flatten.join(' ')}>"
  end

  def new_record?
    @id.nil?
  end

  def save
    @id ||= String.random(2)
  end
end

class Parent < Human
  has_many(:children).dynamic {|assoc,p| assoc.as(p.gender == :female ? :mother : :father)}
end

class Child < Human
  attr_accessor :mother_id, :father_id
  def parent_id=(v)
    raise "Parent must have a gender!"
  end
  attr_reader :cid
  def self.key
    :cid
  end

  belongs_to(:father, :class_name => :parent).mirrors(:children)
  belongs_to(:mother, :class_name => :parent).mirrors(:children)

  has_many(:siblings, :class_name => :child).
    dynamic { |assoc,a| assoc.scope(:conditions => proc {|b| a != b && (a.father_id == b.father_id || a.mother_id == b.mother_id)}) }

  has_many(:half_siblings, :class_name => :child).
    dynamic { |assoc,a| assoc.scope(:conditions => proc {|b| a != b && ((a.father_id == b.father_id && a.mother_id != b.mother_id) || (a.mother_id == b.mother_id && a.father_id != b.father_id))}) }

  def parents
    association_set([:father, :mother])
  end
  def brothers
    association(:siblings).scope(:gender => :male).set
  end
  def sisters
    association(:siblings).scope(:gender => :female).set
  end
  def half_brothers
    association(:half_siblings).scope(:gender => :male).set
  end
  def half_sisters
    association(:half_siblings).scope(:gender => :female).set
  end
end

if respond_to?(:describe)
  describe Parent do
    it "should make parents" do
      @dwayne = Parent.new(:gender => :male)
      @dwayne.save
      @dwayne.should be_is_a(Parent)
      @dwayne.id.should_not be_nil
      @dwayne.should_not be_new_record
      @dwayne.children.should be_is_a(SimpleMapper::Associations::Association::Set)
    end

    it "should make children" do
      @rachel = Child.new
      @rachel.should be_is_a(Child)
      @rachel.should be_respond_to(:father=)
    end
  end

  describe Child do
    before do
      @dwayne = Parent.new(:gender => :male)
      @dwayne.save
      @pam = Parent.new(:gender => :female)
      @pam.save
      @rachel = Child.new
      @daniel = Child.new
      @ben = Child.new
    end

    it "should associate children" do
      @rachel.father = @dwayne
      # Child.should_not receive(:all)
      @dwayne.children.should be_include(@rachel)
      @dwayne.children.should_not be_include(@ben)
      @pam.children.should_not be_include(@ben)
    end

    it "should find associated objects" do
      @rachel.mother_id = @pam.id
      @pam.children.should be_include(@rachel)
    end
  end

  describe "parent associations" do
    it "should combine father and mother associations to make a parent association set" do
      
    end
  end

  describe "siblings" do
    before do
      @dwayne = Parent.new(:gender => :male, :name => 'Dwayne')
      @dwayne.save
      @pam = Parent.new(:gender => :female, :name => 'Pam')
      @pam.save
      @rachel = Child.new(:gender => :female, :name => 'Rachel')
      @rachel.father = @dwayne
      @rachel.mother = @pam
      @daniel = Child.new(:gender => :male, :name => 'Daniel')
      @dwayne.children << @daniel
      @pam.children << @daniel
      @ben = Child.new(:gender => :male, :name => 'Ben')
      @ben.father = @dwayne
    end

    it "should associate siblings" do
      @rachel.siblings.should be_include(@daniel)
      @rachel.siblings.should be_include(@ben)
      @rachel.siblings.should_not be_include(@rachel)
    end

    it "should associate brothers" do
      @rachel.brothers.should be_include(@daniel)
      @rachel.brothers.should be_include(@ben)
      @rachel.brothers.should_not be_include(@rachel)
    end

    it "should associate half-siblings" do
      @rachel.half_siblings.should be_include(@ben)
      @rachel.half_siblings.should_not be_include(@daniel)
      @ben.half_brothers.should be_include(@daniel)
      @ben.half_brothers.should_not be_include(@rachel)
      @ben.half_sisters.should be_include(@rachel)
      @ben.half_sisters.should_not be_include(@daniel)
    end

    it "should keep an object's association implementations distinct so they don't conflict" do
      @ben.brothers
      @ben.siblings.should be_include(@rachel)
    end
  end
else
  @dwayne = Parent.new(:gender => :male, :name => 'Dwayne')
  @dwayne.save
  @pam = Parent.new(:gender => :female, :name => 'Pam')
  @pam.save
  @rachel = Child.new(:gender => :female, :name => 'Rachel')
  @rachel.father = @dwayne
  @rachel.mother = @pam
  @daniel = Child.new(:gender => :male, :name => 'Daniel')
  @dwayne.children << @daniel
  @pam.children << @daniel
  @ben = Child.new(:gender => :male, :name => 'Ben')
  @ben.father = @dwayne
end
