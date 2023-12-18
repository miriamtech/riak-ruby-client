# Copyright 2010-present Basho Technologies, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'

describe Riak::SecondaryIndex do
  before(:each) do
    @client = Riak::Client.new
    @bucket = Riak::Bucket.new @client, 'foo'
  end

  describe "initialization" do
    it "accepts a bucket, index name, and scalar" do
      expect { Riak::SecondaryIndex.new @bucket, 'asdf', 'aaaa' }.not_to raise_error
      expect { Riak::SecondaryIndex.new @bucket, 'asdf', 12345 }.not_to raise_error
    end

    it "accepts a bucket, index name, and a range" do
      expect { Riak::SecondaryIndex.new @bucket, 'asdf', 'aaaa'..'zzzz' }.not_to raise_error
      expect { Riak::SecondaryIndex.new @bucket, 'asdf', 1..5 }.not_to raise_error
    end
  end

  describe "operation" do
    before(:each) do
      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      @args = [@bucket, 'asdf', 'aaaa'..'zzzz', {}]
      @index = Riak::SecondaryIndex.new *@args

      expect(@backend).to receive(:get_index).with(*@args).and_return(%w{abcd efgh})
    end

    it "returns an array of keys" do
      @results = @index.keys
      expect(@results).to be_a Array
      expect(@results.first).to be_a String
    end
    it "returns an array of values" do
      expect(@backend).to receive(:fetch_object).with(@bucket, 'abcd', {}).and_return('abcd')
      expect(@backend).to receive(:fetch_object).with(@bucket, 'efgh', {}).and_return('efgh')

      @results = @index.values
      expect(@results).to be_a Array
      expect(@results.length).to eq(2)
    end
  end

  describe "streaming" do
    it "streams keys into a block" do
      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      @args = [@bucket, 'asdf', 'aaaa'..'zzzz', {stream: true}]
      @index = Riak::SecondaryIndex.new *@args

      expect(@backend).to receive(:get_index).with(*@args).and_yield('abcd').and_yield('efgh')

      @index.keys {|b| :noop }
    end
  end

  describe "pagination" do
    it "supports max_results" do
      @max_results = 5

      @expected_collection = Riak::IndexCollection.new_from_json({
        'keys' => %w{aaaa bbbb cccc dddd eeee},
        'continuation' => 'examplecontinuation'
      }.to_json)

      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      expect(@backend).
        to receive(:get_index).
        with(
             @bucket,
             'asdf',
             ('aaaa'..'zzzz'),
             { max_results: @max_results },
             ).
        and_return(@expected_collection)
      allow(@backend).to receive(:get_server_version).and_return('1.4.0')


      @index = Riak::SecondaryIndex.new(
                                        @bucket,
                                        'asdf',
                                        'aaaa'..'zzzz',
                                        :max_results => @max_results
                                        )

      @results = @index.keys
      expect(@results).to be_an Array
      expect(@results).to eq(@expected_collection)
      expect(@results.length).to eq(@max_results)
    end

    it "supports continuations" do
      @max_results = 5

      @expected_collection = Riak::IndexCollection.new_from_json({
        'keys' => %w{ffff gggg hhhh}
      }.to_json)

      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      expect(@backend).
        to receive(:get_index).
        with(
             @bucket,
             'asdf',
             ('aaaa'..'zzzz'),
             {
               max_results: @max_results,
               continuation: 'examplecontinuation',
             },
             ).
        and_return(@expected_collection)
      allow(@backend).to receive(:get_server_version).and_return('1.4.0')


      @index = Riak::SecondaryIndex.new(
                                        @bucket,
                                        'asdf',
                                        'aaaa'..'zzzz',
                                        max_results: @max_results,
                                        continuation: 'examplecontinuation'
                                        )

      @results = @index.keys
      expect(@results).to be_an Array
      expect(@results).to eq(@expected_collection)
    end

    it "supports a next_page method" do
      @max_results = 5

      @expected_collection = Riak::IndexCollection.new_from_json({
        'keys' => %w{aaaa bbbb cccc dddd eeee},
        'continuation' => 'examplecontinuation'
      }.to_json)

      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      expect(@backend).
        to receive(:get_index).
        once.
        with(
             @bucket,
             'asdf',
             ('aaaa'..'zzzz'),
             { max_results: @max_results },
             ).
        and_return(@expected_collection)
      allow(@backend).to receive(:get_server_version).and_return('1.4.0')


      @index = Riak::SecondaryIndex.new(
                                        @bucket,
                                        'asdf',
                                        'aaaa'..'zzzz',
                                        :max_results => @max_results
                                        )

      @results = @index.keys
      expect(@results).to eq(@expected_collection)

      @second_collection = Riak::IndexCollection.new_from_json({
        'keys' => %w{ffff gggg hhhh}
      }.to_json)
      expect(@backend).
        to receive(:get_index).
        once.
        with(
             @bucket,
             'asdf',
             ('aaaa'..'zzzz'),
             {
               max_results: @max_results,
               continuation: 'examplecontinuation',
             },
             ).
        and_return(@second_collection)

      @second_page = @index.next_page
      @second_results = @second_page.keys
      expect(@second_results).to eq(@second_collection)
    end
  end

  describe "return_terms" do
    it "optionally gives the index value" do
      @expected_collection = Riak::IndexCollection.new_from_json({
        'results' => [
          {'aaaa' => 'aaaa'},
          {'bbbb' => 'bbbb'},
          {'bbbb' => 'bbbb2'}
        ]
        }.to_json)


      @backend = double 'Backend'
      allow(@client).to receive(:backend).and_yield(@backend)
      expect(@backend).
        to receive(:get_index).
        with(
             @bucket,
             'asdf',
             ('aaaa'..'zzzz'),
             { return_terms: true },
             ).
        and_return(@expected_collection)
      allow(@backend).to receive(:get_server_version).and_return('1.4.0')


      @index = Riak::SecondaryIndex.new(
                                        @bucket,
                                        'asdf',
                                        'aaaa'..'zzzz',
                                        :return_terms => true
                                        )

      @results = @index.keys
      expect(@results).to be_an Array
      expect(@results).to eq(@expected_collection)
      expect(@results.with_terms).to eq({
        'aaaa' => %w{aaaa},
        'bbbb' => %w{bbbb bbbb2}
      })
    end
  end
end
