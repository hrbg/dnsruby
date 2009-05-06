#--
#Copyright 2007 Nominet UK
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License. 
#You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0 
#
#Unless required by applicable law or agreed to in writing, software 
#distributed under the License is distributed on an "AS IS" BASIS, 
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
#See the License for the specific language governing permissions and 
#limitations under the License.
#++
require 'rubygems'
require 'test/unit'
require 'dnsruby'
include Dnsruby
class TestSingleResolver < Test::Unit::TestCase
  Thread::abort_on_exception = true
  #  Dnsruby.log.level=Logger::DEBUG
  
  def setup
    Dnsruby::Config.reset
  end
  
  Rrs = [
    {
      :type   		=> Types.A,
      :name   		=> 'a.t.dnsruby.validation-test-servers.nominet.org.uk',
      :address 	=> '10.0.1.128'
    },
    {
      :type		=> Types::MX,
      :name		=> 'mx.t.dnsruby.validation-test-servers.nominet.org.uk',
      :exchange	=> 'a.t.dnsruby.validation-test-servers.nominet.org.uk',
      :preference 	=> 10
    },
    {
      :type		=> 'CNAME',
      :name		=> 'cname.t.dnsruby.validation-test-servers.nominet.org.uk',
      :domainname		=> 'a.t.dnsruby.validation-test-servers.nominet.org.uk'
    },
    {
      :type		=> Types.TXT,
      :name		=> 'txt.t.dnsruby.validation-test-servers.nominet.org.uk',
      :strings		=> ['Net-DNS']
    }		
  ]		
  
  def test_simple
    res = SingleResolver.new()
    m = res.query("a.t.dnsruby.validation-test-servers.nominet.org.uk")
  end
  
  def test_timeout
    if (!RUBY_PLATFORM=~/darwin/)
      # Run a query which will not respond, and check that the timeout works
      begin
        res = SingleResolver.new("10.0.1.128")
        res.port = port
        res.packet_timeout=1
        m = res.query("a.t.dnsruby.validation-test-servers.nominet.org.uk")
        fail
      rescue ResolvTimeout
      end
    end
  end
  
  def test_queue_timeout
    port = 46129
    if (!RUBY_PLATFORM=~/darwin/)
      res = SingleResolver.new("10.0.1.128")
      res.port = port
      res.packet_timeout=1
      q = Queue.new
      msg = Message.new("a.t.dnsruby.validation-test-servers.nominet.org.uk")
      res.send_async(msg, q, msg)
      id,ret, error = q.pop
      assert(id==msg)
      assert(ret==nil)
      assert(error.class == ResolvTimeout)
    end
  end
  
  def test_queries
    res = SingleResolver.new
    
    Rrs.each do |data|
      packet=nil
      2.times do 
        begin
          packet = res.query(data[:name], data[:type])
        rescue ResolvTimeout
        end
        break if packet
      end
      assert(packet)
      assert_equal(packet.question[0].qclass,    'IN',             'Class correct'           )
      
      assert(packet, "Got an answer for #{data[:name]} IN #{data[:type]}")
      assert_equal(1, packet.header.qdcount, 'Only one question')
      assert_equal(1, packet.header.ancount, 'Got single answer')
      
      question = (packet.question)[0]
      answer   = (packet.answer)[0]
      
      assert(question,                           'Got question'            )
      assert_equal(data[:name],  question.qname.to_s,  'Question has right name' )
      assert_equal(Types.new(data[:type]),  question.qtype,  'Question has right type' )
      assert_equal('IN',             question.qclass.string, 'Question has right class')
      
      assert(answer)
      assert_equal(answer.klass,    'IN',             'Class correct'           )
      
      
      data.keys.each do |meth| 
        if (meth == :type)
          assert_equal(Types.new(data[meth]).to_s, answer.send(meth).to_s, "#{meth} correct (#{data[:name]})") 
        else       
          assert_equal(data[meth].to_s, answer.send(meth).to_s, "#{meth} correct (#{data[:name]})") 
        end
      end
    end # do
  end # test_queries
  
  # @TODO@ Although the test_thread_stopped test runs in isolation, it won't run as part
  # of the whole test suite (ts_dnsruby.rb). Commented out until I can figure out how to 
  # get Test::Unit to run this one sequentially...  
  #  def test_thread_stopped
  #    res=SingleResolver.new
  #    # Send a query, and check select_thread running.
  #    m = res.query("example.com")
  #    assert(Dnsruby::SelectThread.instance.select_thread_alive?)
  #    # Wait a second, and check select_thread stopped.
  #    sleep(2)
  #    assert(!Dnsruby::SelectThread.instance.select_thread_alive?)
  #    # Send another query, and check select_thread running.
  #    m = res.query("example.com")
  #    assert(Dnsruby::SelectThread.instance.select_thread_alive?)
  #  end
  
  def test_res_config
    res = Dnsruby::SingleResolver.new
    
    res.server=('a.t.dnsruby.validation-test-servers.nominet.org.uk')
    ip = res.server
    assert_equal('10.0.1.128', ip, 'nameserver() looks up IP.')
    
    res.server=('cname.t.dnsruby.validation-test-servers.nominet.org.uk')
    ip = res.server
    assert_equal(ip, '10.0.1.128', 'nameserver() looks up cname.')
  end
  
  def test_truncated_response
    res = SingleResolver.new
#    print "Dnssec = #{res.dnssec}\n"
    res.server=('ns0.validation-test-servers.nominet.org.uk')
    res.packet_timeout = 15
    m = res.query("overflow.dnsruby.validation-test-servers.nominet.org.uk", 'txt')
    assert(m.header.ancount == 61, "61 answer records expected, got #{m.header.ancount}")
    assert(!m.header.tc, "Message was truncated!")
  end

  def test_illegal_src_port
    # Try to set src_port to an illegal value - make sure error raised, and port OK
    res = SingleResolver.new
    tests = [53, 387, 1265, 3210, 48619]
    tests.each do |bad_port|
      begin
        res.src_port = bad_port
        fail("bad port #{bad_port}")
      rescue
      end
    end
  end
  
  def test_add_src_port
    # Try setting and adding port ranges, and invalid ports, and 0.
    res = SingleResolver.new
    res.src_port = [56789,56790, 56793]
    assert(res.src_port == [56789,56790, 56793])
    res.src_port = 56889..56891
    assert(res.src_port == [56889,56890,56891])
    res.add_src_port(60000..60002)
    assert(res.src_port == [56889,56890,56891,60000,60001,60002])
    res.add_src_port([60004,60005])
    assert(res.src_port == [56889,56890,56891,60000,60001,60002,60004,60005])
    res.add_src_port(60006)
    assert(res.src_port == [56889,56890,56891,60000,60001,60002,60004,60005,60006])
    # Now test invalid src_ports
    tests = [0, 53, [60007, 53], [60008, 0], 55..100]
    tests.each do |x|
      begin
        res.add_src_port(x)
        fail()
      rescue
      end
    end
    assert(res.src_port == [56889,56890,56891,60000,60001,60002,60004,60005,60006])
  end
end