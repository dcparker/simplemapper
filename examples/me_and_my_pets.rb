class Person < SimpleMapper::Base
  include SimpleMapper::Persistence
  has :properties
    identifier :id
    properties :first_name, :last_name
    properties :age, :birthdate
  has :associations
    has_one :dog
    has_many :cats
    def pets
      association_set([:dog, :cats])
    end
end

class Dog < SimpleMapper::Base
  has :properties
    identifier :name
    property :name
    properties :size, :weight
  has :associations
    belongs_to(:owner, :class_name => :person)
    # Dog thinks cats are his friends, but cat thinks dog is enemy
    has_many(:friends, :class_name => :cat).as(:enemy)
end

class Cat
  include SimpleMapper::Persistence
  has :properties
    identifier :name
    property :enemy_name
  has :associations
    belongs_to(:owner, :class_name => :person)
    # Cat thinks dog is his enemy, but dog thinks cats are friends
    belongs_to(:enemy, :class_name => :dog).as(:friends)
end
