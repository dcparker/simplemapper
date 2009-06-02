# SimpleMapper. The purpose of this is to provide Ruby models with Persistence in the simplest way possible.
# Like all ORM's it must be based on two components: Format and Connection. The aim is to stay out of the way
# as much as possible: Format will be performed by calling, for example a Person class with the xml format:
# '@person.to_xml', and likewise 'Person.from_xml'.
# 
# SimpleMapper will hold no concept of primary keys or even of properties or attributes. It will be data-agnostic.
# It will simply handle the transformation and communication of data while providing a common method interface
# in order to remove the model from the persistence.
# 
# The connection class will simply work with the idea of messages sent by adapters. All adapters must respond to these methods
# appropriately: get, put, post, and delete. These correspond directly to HTTP methods, and correspond to SQL commands
# in the order of SELECT, UPDATE, INSERT, and DELETE. It is up to an extraneous library/gem to handle conversions of special
# "finder" options, like converting an options hash to a sql SELECT request, or mapping an options hash to an HTTP request.
# It is purposed to make it as light and simple as possible to plug these in.

require File.expand_path(File.dirname(__FILE__) + '/simple_mapper/base')
