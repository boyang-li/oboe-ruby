# Copyright (c) 2015 AppNeta, Inc.
# All rights reserved.

require 'minitest_helper'

unless ENV['TV_MONGO_SERVER']
  ENV['TV_MONGO_SERVER'] = "127.0.0.1:27017"
end

if RUBY_VERSION >= '1.9.3'
  # Moped is tested against MRI 1.9.3, 2.0.0, and JRuby (1.9).

  describe "Moped" do
    before do
      clear_all_traces
      @session = Moped::Session.new([ ENV['TV_MONGO_SERVER'] ])
      @session.use :moped_test
      @users = @session[:users]
      @users.insert({ :name => "Syd", :city => "Boston" })

      # These are standard entry/exit KVs that are passed up with all moped operations
      @entry_kvs = {
        'Layer' => 'mongo',
        'Label' => 'entry',
        'Flavor' => 'mongodb',
        'Database' => 'moped_test',
        'RemoteHost' => ENV['TV_MONGO_SERVER'].split(':')[0],
        'RemotePort' => ENV['TV_MONGO_SERVER'].split(':')[1].to_i }

      @exit_kvs = { 'Layer' => 'mongo', 'Label' => 'exit' }
      @collect_backtraces = TraceView::Config[:moped][:collect_backtraces]
    end

    after do
      TraceView::Config[:moped][:collect_backtraces] = @collect_backtraces
    end

    it 'Stock Moped should be loaded, defined and ready' do
      defined?(::Moped).wont_match nil
      defined?(::Moped::Database).wont_match nil
      defined?(::Moped::Indexes).wont_match nil
      defined?(::Moped::Query).wont_match nil
      defined?(::Moped::Collection).wont_match nil
    end

    it 'Moped should have traceview methods defined' do
      #::Moped::Database
      TraceView::Inst::Moped::DB_OPS.each do |m|
        ::Moped::Database.method_defined?("#{m}_with_traceview").must_equal true
      end
      ::Moped::Database.method_defined?(:extract_trace_details).must_equal true
      ::Moped::Database.method_defined?(:command_with_traceview).must_equal true
      ::Moped::Database.method_defined?(:drop_with_traceview).must_equal true

      #::Moped::Indexes
      TraceView::Inst::Moped::INDEX_OPS.each do |m|
        ::Moped::Indexes.method_defined?("#{m}_with_traceview").must_equal true
      end
      ::Moped::Indexes.method_defined?(:extract_trace_details).must_equal true
      ::Moped::Indexes.method_defined?(:create_with_traceview).must_equal true
      ::Moped::Indexes.method_defined?(:drop_with_traceview).must_equal true

      #::Moped::Query
      TraceView::Inst::Moped::QUERY_OPS.each do |m|
        ::Moped::Query.method_defined?("#{m}_with_traceview").must_equal true
      end
      ::Moped::Query.method_defined?(:extract_trace_details).must_equal true

      #::Moped::Collection
      TraceView::Inst::Moped::COLLECTION_OPS.each do |m|
        ::Moped::Collection.method_defined?("#{m}_with_traceview").must_equal true
      end
      ::Moped::Collection.method_defined?(:extract_trace_details).must_equal true
    end

    it 'should trace command' do
      # TODO: This randomly fails for a yet unknown reason.
      skip
      TraceView::API.start_trace('moped_test', '', {}) do
        command = {}
        command[:mapreduce] = "users"
        command[:map] = "function() { emit(this.name, 1); }"
        command[:reduce] = "function(k, vals) { var sum = 0;" +
          " for(var i in vals) sum += vals[i]; return sum; }"
        command[:out] = "inline: 1"
        @session.command(command)
      end

      traces = get_all_traces

      traces.count.must_equal 4
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "map_reduce"
      traces[1]['Map_Function'].must_equal "function() { emit(this.name, 1); }"
      traces[1]['Reduce_Function'].must_equal "function(k, vals) { var sum = 0;" +
        " for(var i in vals) sum += vals[i]; return sum; }"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)
    end

    it 'should trace drop_collection' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.drop
        @session.drop
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "drop_collection"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "drop_database"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace create_index, indexes and drop_indexes' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.indexes.create({:name => 1}, {:unique => true})
        @users.indexes.drop
      end

      traces = get_all_traces

      traces.count.must_equal 10
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "indexes"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "create_index"
      traces[3]['Key'].must_equal "{\"name\":1}"
      traces[3]['Options'].must_equal "{\"unique\":true}"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)

      validate_event_keys(traces[5], @entry_kvs)
      traces[5]['QueryOp'].must_equal "indexes"
      traces[5]['Collection'].must_equal "users"
      traces[5].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[6], @exit_kvs)

      validate_event_keys(traces[7], @entry_kvs)
      traces[7]['QueryOp'].must_equal "drop_indexes"
      traces[7]['Key'].must_equal "all"
      traces[7].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[8], @exit_kvs)
    end

    it 'should trace find and count' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find.count
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "count"
      traces[3]['Query'].must_equal "all"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find and sort' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").sort(:city => 1, :created_at => -1)
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "sort"
      traces[3]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Order'].must_equal "{:city=>1, :created_at=>-1}"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find with limit' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").limit(1)
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "limit"
      traces[3]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Limit'].must_equal "1"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find with distinct' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").distinct(:city)
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "distinct"
      traces[3]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Key'].must_equal "city"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find and update' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").update({:name => "Tool"}, [:multi])
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "update"
      traces[3]['Update_Document'].must_equal "{\"name\":\"Tool\"}"
      traces[3]['Flags'].must_equal "[:multi]"
      traces[3]['Collection'].must_equal "users"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find and update_all' do
      @users.insert(:name => "Mary")
      mary_count = @users.find(:name => "Mary").count
      tool_count = @users.find(:name => "Tool").count
      tool_count.must_equal 0

      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").update_all({:name => "Tool"})
      end
      new_tool_count.must_equal mary_count

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "update_all"
      traces[3]['Update_Document'].must_equal "{\"name\":\"Tool\"}"
      traces[3]['Collection'].must_equal "users"
      traces[3]['Flags'].must_equal "[:multi]"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find and upsert' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Tool").upsert({:name => "Mary"})
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Tool\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "upsert"
      traces[3]['Query'].must_equal "{\"name\":\"Tool\"}"
      traces[3]['Update_Document'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Collection'].must_equal "users"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace find and explain' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").explain
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "explain"
      traces[3]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Collection'].must_equal "users"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace 3 types of find and modify calls' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:likes => 1).modify({ "$set" => { :name => "Tool" }}, :upsert => true)
        @users.find.modify({:query => { "$inc" => { :likes => 1 }}}, :new => true)
        @users.find.modify({:query => {}}, :remove => true)
      end

      traces = get_all_traces

      traces.count.must_equal 14
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"likes\":1}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "modify"
      traces[3]['Update_Document'].must_equal "{\"likes\":1}"
      traces[3]['Collection'].must_equal "users"
      traces[3]['Options'].must_equal "{\"upsert\":true}"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)

      validate_event_keys(traces[7], @entry_kvs)
      traces[7]['QueryOp'].must_equal "modify"
      traces[7]['Update_Document'].must_equal "all"
      traces[7]['Collection'].must_equal "users"
      traces[7]['Options'].must_equal "{\"new\":true}"
      traces[7]['Change'].must_equal "{\"query\":{\"$inc\":{\"likes\":1}}}"
      traces[7].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[8], @exit_kvs)

      validate_event_keys(traces[11], @entry_kvs)
      traces[11]['Collection'].must_equal "users"
      traces[11]['QueryOp'].must_equal "modify"
      traces[11]['Update_Document'].must_equal "all"
      traces[11]['Change'].must_equal "{\"query\":{}}"
      traces[11]['Options'].must_equal "{\"remove\":true}"
      traces[11].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[12], @exit_kvs)
    end

    it 'should trace remove' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Tool").remove
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Tool\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "remove"
      traces[3]['Query'].must_equal "{\"name\":\"Tool\"}"
      traces[3]['Collection'].must_equal "users"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace remove_all' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").remove_all
      end

      traces = get_all_traces

      traces.count.must_equal 6
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "find"
      traces[1]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)

      validate_event_keys(traces[3], @entry_kvs)
      traces[3]['QueryOp'].must_equal "remove_all"
      traces[3]['Query'].must_equal "{\"name\":\"Mary\"}"
      traces[3]['Collection'].must_equal "users"
      traces[3].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[4], @exit_kvs)
    end

    it 'should trace aggregate' do
      TraceView::API.start_trace('moped_test', '', {}) do
        @users.aggregate(
          {'$match' => {:name => "Mary"}},
          {'$group' => {"_id" => "$name"}}
        )
      end

      traces = get_all_traces

      traces.count.must_equal 4
      validate_outer_layers(traces, 'moped_test')

      validate_event_keys(traces[1], @entry_kvs)
      traces[1]['QueryOp'].must_equal "aggregate"
      traces[1]['Query'].must_equal "[{\"$match\"=>{:name=>\"Mary\"}}, {\"$group\"=>{\"_id\"=>\"$name\"}}]"
      traces[1]['Collection'].must_equal "users"
      traces[1].has_key?('Backtrace').must_equal TraceView::Config[:moped][:collect_backtraces]
      validate_event_keys(traces[2], @exit_kvs)
    end

    it "should obey :collect_backtraces setting when true" do
      TraceView::Config[:moped][:collect_backtraces] = true

      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").limit(1)
      end

      traces = get_all_traces
      layer_has_key(traces, 'mongo', 'Backtrace')
    end

    it "should obey :collect_backtraces setting when false" do
      TraceView::Config[:moped][:collect_backtraces] = false

      TraceView::API.start_trace('moped_test', '', {}) do
        @users.find(:name => "Mary").limit(1)
      end

      traces = get_all_traces
      layer_doesnt_have_key(traces, 'mongo', 'Backtrace')
    end
  end

end
