require 'spec_helper'
require 'dragonfly/spec/data_store_examples'

describe Dragonfly::FileDataStore do

  def touch_file(filename)
    FileUtils.mkdir_p(File.dirname(filename))
    FileUtils.touch(filename)
  end

  def assert_exists(path)
    File.exists?(path).should be_true
  end

  def assert_does_not_exist(path)
    File.exists?(path).should be_false
  end

  let (:app) { test_app }
  let (:content) { Dragonfly::Content.new(app, 'goobydoo') }
  let (:new_content) { Dragonfly::Content.new(app) }

  describe "with a given root path" do

    before(:each) do
      @data_store = Dragonfly::FileDataStore.new(:root_path => 'tmp/file_data_store_test')
    end

    after(:each) do
      # Clean up created files
      FileUtils.rm_rf("#{@data_store.root_path}")
    end

    it_should_behave_like 'data_store'

    describe "write" do

      before(:each) do
        # Set 'now' to a date in the past
        Time.stub!(:now).and_return Time.mktime(1984,"may",4,14,28,1)
        @file_pattern_prefix_without_root = '1984/05/04/14_28_01_0_'
        @file_pattern_prefix = "#{@data_store.root_path}/#{@file_pattern_prefix_without_root}"
      end

      it "should store the file in a folder based on date, with default filename" do
        @data_store.write(content)
        assert_exists "#{@file_pattern_prefix}file"
      end

      it "should use the content name if it exists" do
        content.should_receive(:name).at_least(:once).and_return('hello.there')
        @data_store.write(content)
        assert_exists "#{@file_pattern_prefix}hello.there"
      end

      it "should get rid of funny characters in the content name" do
        content.should_receive(:name).at_least(:once).and_return('A Picture with many spaces in its name (at 20:00 pm).png')
        @data_store.write(content)
        assert_exists "#{@file_pattern_prefix}A_Picture_with_many_spaces_in_its_name_at_20_00_pm_.png"
      end

      it "stores meta as YAML" do
        content.meta = {'wassup' => 'doc'}
        @data_store.write(content)
        File.read("#{@file_pattern_prefix}file.meta.yml").should =~ /---\s+wassup: doc/
      end

      describe "when the filename already exists" do

        it "should use a different filename" do
          touch_file("#{@file_pattern_prefix}file")
          @data_store.should_receive(:disambiguate).with("#{@file_pattern_prefix}file").and_return("#{@file_pattern_prefix}file_2")
          @data_store.write(content)
          assert_exists "#{@file_pattern_prefix}file_2"
        end

        it "should use a different filename taking into account the name and ext" do
          content.should_receive(:name).at_least(:once).and_return('hello.png')
          touch_file("#{@file_pattern_prefix}hello.png")
          @data_store.should_receive(:disambiguate).with("#{@file_pattern_prefix}hello.png").and_return("#{@file_pattern_prefix}blah.png")
          @data_store.write(content)
        end

        it "should keep trying until it finds a free filename" do
          touch_file("#{@file_pattern_prefix}file")
          touch_file("#{@file_pattern_prefix}file_2")
          @data_store.should_receive(:disambiguate).with("#{@file_pattern_prefix}file").and_return("#{@file_pattern_prefix}file_2")
          @data_store.should_receive(:disambiguate).with("#{@file_pattern_prefix}file_2").and_return("#{@file_pattern_prefix}file_3")
          @data_store.write(content)
          assert_exists "#{@file_pattern_prefix}file_3"
        end

        describe "specifying the uid" do
          it "should allow for specifying the path to use" do
            @data_store.write(content, :path => 'hello/there/mate.png')
            assert_exists "#{@data_store.root_path}/hello/there/mate.png"
          end
          it "should correctly disambiguate if the file exists" do
            touch_file("#{@data_store.root_path}/hello/there/mate.png")
            @data_store.should_receive(:disambiguate).with("#{@data_store.root_path}/hello/there/mate.png").and_return("#{@data_store.root_path}/hello/there/mate_2.png")
            @data_store.write(content, :path => 'hello/there/mate.png')
            assert_exists "#{@data_store.root_path}/hello/there/mate_2.png"
          end
        end

      end

      describe "return value" do

        it "should return the filepath without the root of the stored file when a file name is not provided" do
          @data_store.write(content).should == "#{@file_pattern_prefix_without_root}file"
        end

        it "should return the filepath without the root of the stored file when a file name is provided" do
          content.should_receive(:name).at_least(:once).and_return('hello.you.png')
          @data_store.write(content).should == "#{@file_pattern_prefix_without_root}hello.you.png"
        end

      end

    end

    describe "disambiguate" do
      it "should add a suffix" do
        @data_store.disambiguate('/some/file').should =~ %r{^/some/file_\w+$}
      end
      it "should add a suffix to the basename" do
        @data_store.disambiguate('/some/file.png').should =~ %r{^/some/file_\w+\.png$}
      end
      it "should be random(-ish)" do
        @data_store.disambiguate('/some/file').should_not == @data_store.disambiguate('/some/file')
      end
    end

    describe "read" do
      it "should be able to read any file, stored or not (and without meta data)" do
        FileUtils.mkdir_p("#{@data_store.root_path}/jelly_beans/are")
        File.open("#{@data_store.root_path}/jelly_beans/are/good", 'w'){|f| f.write('hey dog') }
        new_content.update(*@data_store.read("jelly_beans/are/good"))
        new_content.data.should == 'hey dog'
        new_content.meta.should == {'name' => 'good'}
      end

      it "should raise if the file path has ../ in it" do
        expect{
          @data_store.read('jelly_beans/../are/good')
        }.to raise_error(Dragonfly::FileDataStore::BadUID)
      end

      it "should not raise if the file path has .. but not ../ in it" do
        @data_store.write(content, :path => 'jelly_beans..good')
        new_content.update(*@data_store.read('jelly_beans..good'))
        new_content.data.should == 'goobydoo'
      end
    end

    describe "destroying" do
      it "should prune empty directories when destroying" do
        uid = @data_store.write(content)
        @data_store.destroy(uid)
        @data_store.root_path.should be_an_empty_directory
      end

      it "should not prune root_path directory when destroying file without directory prefix in path" do
        uid = @data_store.write(content, :path => 'mate.png')
        @data_store.destroy(uid)
        @data_store.root_path.should be_an_empty_directory
      end

      it "should raise if the file path has ../ in it" do
        expect{
          @data_store.destroy('jelly_beans/../are/good')
        }.to raise_error(Dragonfly::FileDataStore::BadUID)
      end
    end

    describe "setting the root_path" do
      it "should allow setting as a pathname" do
        @data_store.root_path = Pathname.new('/some/thing')
        @data_store.root_path.should == '/some/thing'
      end
    end

    describe "relative paths" do
      let(:store) { Dragonfly::FileDataStore.new }
      let(:relative_path) { "2011/02/11/picture.jpg" }
      let(:absolute_path) { "#{root_path}#{relative_path}" }
      let(:root_path) { "/path/to/file/" }

      before do
        store.root_path = root_path
      end

      subject { store.send :relative, absolute_path }

      it { should == relative_path }

      context "where root path contains spaces" do
        let(:root_path) { "/path/to/file name/" }
        it { should == relative_path }
      end
      context "where root path contains special chars" do
        let(:root_path) { "/path/to/file name (Special backup directory)/" }
        it { should == relative_path }
      end
    end

    describe "turning meta off" do
      before(:each) do
        @data_store.store_meta = false
        content.meta = {'bitrate' => '35', 'name' => 'danny.boy'}
      end

      it "should not write a meta file" do
        uid = @data_store.write(content)
        assert_does_not_exist(File.join(@data_store.root_path, "#{uid}.meta"))
        assert_does_not_exist(File.join(@data_store.root_path, "#{uid}.meta.yml"))
      end

      it "should return an empty hash on read" do
        uid = @data_store.write(content)
        new_content.update(*@data_store.read(uid))
        new_content.meta['bitrate'].should be_nil
      end

      it "should still destroy the meta file if it exists" do
        @data_store.store_meta = true
        uid = @data_store.write(content)
        @data_store.store_meta = false
        @data_store.destroy(uid)
        @data_store.root_path.should be_an_empty_directory
      end

      it "should still destroy properly if meta is on but the meta file doesn't exist" do
        uid = @data_store.write(content)
        @data_store.store_meta = true
        @data_store.destroy(uid)
        @data_store.root_path.should be_an_empty_directory
      end
    end

    describe "urls for serving directly" do
      before(:each) do
        @uid = 'some/path/to/file.png'
        @data_store.root_path = '/var/tmp/eggs'
      end

      it "should raise an error if called without configuring" do
        expect{
          @data_store.url_for(@uid)
        }.to raise_error(Dragonfly::FileDataStore::UnableToFormUrl)
      end

      it "should work as expected when the the server root is above the root path" do
        @data_store.server_root = '/var/tmp'
        @data_store.url_for(@uid).should == '/eggs/some/path/to/file.png'
      end

      it "should work as expected when the the server root is the root path" do
        @data_store.server_root = '/var/tmp/eggs'
        @data_store.url_for(@uid).should == '/some/path/to/file.png'
      end

      it "should work as expected when the the server root is below the root path" do
        @data_store.server_root = '/var/tmp/eggs/some/path'
        @data_store.url_for(@uid).should == '/to/file.png'
      end

      it "should allow setting the server_root as a pathname" do
        @data_store.server_root = Pathname.new('/var/tmp/eggs/some/path')
        @data_store.url_for(@uid).should == '/to/file.png'
      end

      it "should raise an error when the server root doesn't coincide with the root path" do
        @data_store.server_root = '/var/blimey/eggs'
        expect{
          @data_store.url_for(@uid)
        }.to raise_error(Dragonfly::FileDataStore::UnableToFormUrl)
      end

      it "should raise an error when the server root doesn't coincide with the uid" do
        @data_store.server_root = '/var/tmp/eggs/some/gooney'
        expect{
          @data_store.url_for(@uid)
        }.to raise_error(Dragonfly::FileDataStore::UnableToFormUrl)
      end
    end

  end

  describe "deprecated meta" do
    let(:data_store){ Dragonfly::FileDataStore.new(:root_path => 'spec/fixtures/deprecated_stored_content')}

    it "still works with old-style meta" do
      new_content.update(*data_store.read('eggs.bonus'))
      new_content.data.should == "Barnicle"
      new_content.meta.should == {'name' => 'eggs.bonus', 'some' => 'meta', 'number' => 5}
    end
  end
end

