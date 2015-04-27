# encoding: utf-8
require 'test_helper'

class HistoryTest < ActiveSupport::TestCase
  current_user = User.lookup( login: 'nicole.braun@zammad.org' )

  test 'ticket' do
    tests = [

      # test 1
      {
        ticket_create: {
          ticket: {
            group_id: Group.lookup( name: 'Users' ).id,
            customer_id: current_user.id,
            owner_id: User.lookup( login: '-' ).id,
            title: 'Unit Test 1 (äöüß)!',
            state_id: Ticket::State.lookup( name: 'new' ).id,
            priority_id: Ticket::Priority.lookup( name: '2 normal' ).id,
            updated_by_id: current_user.id,
            created_by_id: current_user.id,
          },
          article: {
              updated_by_id: current_user.id,
              created_by_id: current_user.id,
              type_id: Ticket::Article::Type.lookup( name: 'phone' ).id,
              sender_id: Ticket::Article::Sender.lookup( name: 'Customer' ).id,
              from: 'Unit Test <unittest@example.com>',
              body: 'Unit Test 123',
              internal: false
          },
        },
        ticket_update: {
          ticket: {
            title: 'Unit Test 1 (äöüß) - update!',
            state_id: Ticket::State.lookup( name: 'open' ).id,
            priority_id: Ticket::Priority.lookup( name: '1 low' ).id,
          },
        },
        history_check: [
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'created',
          },
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'updated',
            history_attribute: 'title',
            value_from: 'Unit Test 1 (äöüß)!',
            value_to: 'Unit Test 1 (äöüß) - update!',
          },
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'updated',
            history_attribute: 'state',
            value_from: 'new',
            value_to: 'open',
            id_from: Ticket::State.lookup( name: 'new' ).id,
            id_to: Ticket::State.lookup( name: 'open' ).id,
          },
          {
            result: true,
            history_object: 'Ticket::Article',
            history_type: 'created',
          },
          {
            result: false,
            history_object: 'User',
            history_type: 'updated',
          },
        ]
      },

      # test 2
      {
        ticket_create: {
          ticket: {
            group_id: Group.lookup( name: 'Users' ).id,
            customer_id: current_user.id,
            owner_id: User.lookup( login: '-' ).id,
            title: 'Unit Test 2 (äöüß)!',
            state_id: Ticket::State.lookup( name: 'new' ).id,
            priority_id: Ticket::Priority.lookup( name: '2 normal' ).id,
            updated_by_id: current_user.id,
            created_by_id: current_user.id,
          },
          article: {
              created_by_id: current_user.id,
              updated_by_id: current_user.id,
              type_id: Ticket::Article::Type.lookup(name: 'phone' ).id,
              sender_id: Ticket::Article::Sender.lookup(name: 'Customer' ).id,
              from: 'Unit Test <unittest@example.com>',
              body: 'Unit Test 123',
              internal: false
          },
        },
        ticket_update: {
          ticket: {
            title: 'Unit Test 2 (äöüß) - update!',
            state_id: Ticket::State.lookup( name: 'open' ).id,
            owner_id: current_user.id,
          },
          article: {
            from: 'Unit 2 Test 2 <unittest@example.com>',
          },
        },
        history_check: [
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'created',
          },
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'updated',
            history_attribute: 'title',
            value_from: 'Unit Test 2 (äöüß)!',
            value_to: 'Unit Test 2 (äöüß) - update!',
          },
          {
            result: true,
            history_object: 'Ticket',
            history_type: 'updated',
            history_attribute: 'owner',
            value_from: '-',
            value_to: 'Nicole Braun',
            id_from: User.lookup( login: '-' ).id,
            id_to: current_user.id,
          },
          {
            result: true,
            history_object: 'Ticket::Article',
            history_type: 'created',
          },
          {
            result: true,
            history_object: 'Ticket::Article',
            history_type: 'updated',
            history_attribute: 'from',
            value_from: 'Unit Test <unittest@example.com>',
            value_to: 'Unit 2 Test 2 <unittest@example.com>',
          },
        ]
      },
    ]
    tickets = []
    tests.each { |test|

      ticket = nil
      article = nil

      # use transaction
      ActiveRecord::Base.transaction do
        ticket = Ticket.create( test[:ticket_create][:ticket])
        test[:ticket_create][:article][:ticket_id] = ticket.id
        article = Ticket::Article.create( test[:ticket_create][:article] )

        assert_equal( ticket.class.to_s, 'Ticket' )
        assert_equal( article.class.to_s, 'Ticket::Article' )

        # update ticket
        if test[:ticket_update][:ticket]
          ticket.update_attributes( test[:ticket_update][:ticket] )
        end
        if test[:ticket_update][:article]
          article.update_attributes( test[:ticket_update][:article] )
        end
      end

      # execute ticket events
      Observer::Ticket::Notification.transaction

      # execute background jobs
      Delayed::Worker.new.work_off

      # remember ticket
      tickets.push ticket

      # check history
      history_check( ticket.history_get, test[:history_check] )
    }

    # delete tickets
    tickets.each { |ticket|
      ticket_id = ticket.id
      ticket.destroy
      found = Ticket.where( id: ticket_id ).first
      assert( !found, 'Ticket destroyed')
    }
  end

  test 'user' do
    tests = [

      # test 1
      {
        user_create: {
          user: {
            login: 'some_login_test',
            firstname: 'Bob',
            lastname: 'Smith',
            email: 'somebody@example.com',
            active: true,
            updated_by_id: current_user.id,
            created_by_id: current_user.id,
          },
        },
        user_update: {
          user: {
            firstname: 'Bob',
            lastname: 'Master',
            email: 'master@example.com',          },
            active: false,
        },
        history_check: [
          {
            result: true,
            history_object: 'User',
            history_type: 'created',
          },
          {
            result: true,
            history_object: 'User',
            history_type: 'updated',
            history_attribute: 'lastname',
            value_from: 'Smith',
            value_to: 'Master',
          },
          {
            result: true,
            history_object: 'User',
            history_type: 'updated',
            history_attribute: 'email',
            value_from: 'somebody@example.com',
            value_to: 'master@example.com',
          },
          {
            result: true,
            history_object: 'User',
            history_type: 'updated',
            history_attribute: 'active',
            value_from: 'true',
            value_to: 'false',
          },
        ],
      },

    ]
    users = []
    tests.each { |test|

      user = nil

      # user transaction
      ActiveRecord::Base.transaction do
        user = User.create( test[:user_create][:user])

        assert_equal( user.class.to_s, 'User' )

        # update user
        if test[:user_update][:user]
          test[:user_update][:user][:active] = false
          user.update_attributes( test[:user_update][:user] )
        end
      end

      # remember user
      users.push user

      # check history
      history_check( user.history_get, test[:history_check] )
    }

    # delete user
    users.each { |user|
      user_id = user.id
      user.destroy
      found = User.where( id: user_id ).first
      assert( !found, 'User destroyed')
    }
  end

  test 'organization' do
    tests = [

      # test 1
      {
        organization_create: {
          organization: {
            name: 'Org äöüß',
            note: 'some note',
            updated_by_id: current_user.id,
            created_by_id: current_user.id,
          },
        },
        organization_update: {
          organization: {
            name: 'Org 123',
            note: 'some note',
          },
        },
        history_check: [
          {
            result: true,
            history_object: 'Organization',
            history_type: 'created',
          },
          {
            result: true,
            history_object: 'Organization',
            history_type: 'updated',
            history_attribute: 'name',
            value_from: 'Org äöüß',
            value_to: 'Org 123',
          },
        ],
      },
    ]
    organizations = []
    tests.each { |test|

      organization = nil

      # user transaction
      ActiveRecord::Base.transaction do
        organization = Organization.create( test[:organization_create][:organization])

        assert_equal( organization.class.to_s, 'Organization' )

        # update organization
        if test[:organization_update][:organization]
          organization.update_attributes( test[:organization_update][:organization] )
        end
      end

      # remember user
      organizations.push organization

      # check history
      history_check( organization.history_get, test[:history_check] )
    }

    # delete user
    organizations.each { |organization|
      organization_id = organization.id
      organization.destroy
      found = Organization.where( id: organization_id ).first
      assert( !found, 'Organization destroyed')
    }
  end


  def history_check( history_list, history_check )
#      puts history_list.inspect
    history_check.each { |check_item|
#        puts '+++++++++++'
#        puts check_item.inspect
      match = false
      history_list.each { |history_item|
        next if match
#          puts '--------'
#          puts history_item.inspect
#          puts history_item.history_object.name
        next if history_item['object'] != check_item[:history_object]
        next if history_item['type'] != check_item[:history_type]
        if check_item[:history_attribute]
          next if check_item[:history_attribute] != history_item['attribute']
        end
        match = true
        if history_item['type'] == check_item[:history_type]
          assert( true, "History type #{history_item['type']} found!")
        end
        if check_item[:history_attribute]
          assert_equal( check_item[:history_attribute], history_item['attribute'], "check history attribute #{check_item[:history_attribute]}")
        end
        if check_item[:value_from]
          assert_equal( check_item[:value_from], history_item['value_from'], "check history :value_from #{history_item['value_from']} ok")
        end
        if check_item[:value_to]
          assert_equal( check_item[:value_to], history_item['value_to'], "check history :value_to #{history_item['value_to']} ok")
        end
        if check_item[:id_from]
          assert_equal( check_item[:id_from], history_item['id_from'], "check history :id_from #{history_item['id_from']} ok")
        end
        if check_item[:id_to]
          assert_equal( check_item[:id_to], history_item['id_to'], "check history :id_to #{history_item['id_to']} ok")
        end
      }
      if check_item[:result]
        assert( match, "history check not matched! #{check_item.inspect}")
      else
        assert( !match, "history check matched but should not! #{check_item.inspect}")
      end
    }
  end

end
