dgram = require 'dgram'
http = require 'http'
path = require 'path'

rest = require 'request'
express = require 'express'

JolokiaSrv = require '../src/jolokiasrv'
Config = require '../src/config'

describe 'JolokiaSrv', ->
  js = null
  config = Config.get()
  config.overrides({ 'template_dir': path.resolve(__dirname, 'templates') })

  beforeEach (done) ->
    js = new JolokiaSrv(0)
    done()

  afterEach (done) ->
    js = null
    done()

  it "should be able to add a client", (done) ->
    url_href = 'http://localhost:1234/jolokia/'
    Object.keys(js.jclients).should.have.length 0
    js.add_client('test', url_href)
    Object.keys(js.jclients).should.include "test"
    js.jclients['test'].client.url.hostname.should.equal 'localhost'
    js.jclients['test'].client.url.port.should.equal '1234'
    js.jclients['test'].client.url.href.should.equal url_href
    assert.equal(js.jclients['test'].template, undefined)
    done()

  it "should be able to return a list of clients", (done) ->
    url_href1 = 'http://localhost:1234/jolokia/'
    url_href2 = 'http://localhost:1235/jolokia/'
    Object.keys(js.jclients).should.have.length 0
    js.add_client('bob', url_href1)
    js.add_client('joe', url_href2)
    clients = js.list_clients()
    clients.should.have.length 2
    clients.should.include 'bob'
    clients.should.include 'joe'
    done()

  it "should be able to remove a client", (done) ->
    url_href1 = 'http://localhost:1234/jolokia/'
    url_href2 = 'http://localhost:1235/jolokia/'
    Object.keys(js.jclients).should.have.length 0
    js.add_client('bob', url_href1)
    js.add_client('joe', url_href2)
    clients = js.list_clients()
    clients.should.have.length 2
    js.remove_client('bob')
    clients = js.list_clients()
    clients.should.have.length 1
    clients.should.include 'joe'
    done()

  it "should be able to add templates from the template directory", (done) ->
    js.load_all_templates () =>
      Object.keys(js.templates).length.should.be.above(0)
      done()

  it "should be able to add a template to a client", (done) ->
    url_href = 'http://localhost:1234/jolokia/'
    js.add_client 'test', url_href, 'test_template'

    assert.equal(js.jclients.hasOwnProperty('test'), true)
    client = js.jclients['test']
    client.hasOwnProperty('client').should.equal true
    client.hasOwnProperty('template').should.equal true
    client['template'].should.equal 'test_template'
    done()

  it "should be able to modify the template of a client", (done) ->
    url_href = 'http://localhost:1234/jolokia/'
    js.add_client 'test', url_href, 'test_template'
    js.add_client 'test', url_href, 'test_template2'

    assert.equal(js.jclients.hasOwnProperty('test'), true)
    client = js.jclients['test']
    client.hasOwnProperty('client').should.equal true
    client.hasOwnProperty('template').should.equal true
    client['template'].should.equal 'test_template2'
    done()

  it "should be able to retrieve detailed info for a client", (done) ->
    js.load_all_templates () =>
      url_href = 'http://localhost:1234/jolokia/'
      js.add_client('test', url_href, 'empty_graph')

      client = js.info_client('test')
      client.mappings.length.should.equal 1
      ainfo = client.mappings[0]
      ainfo.mbean.should.equal 'java.lang:somegroup'
      ainfo.attributes.length.should.equal 1
      ainfo.attributes[0].name.should.equal 'someattr'
      Object.keys(ainfo.attributes[0].graph).length.should.equal 0
      done()

  it "should be able to retrieve detailed info for all clients", (done) =>
    js.load_all_templates () =>
      url_href = 'http://localhost:1234/jolokia/'
      js.add_client 'test',  url_href, 'empty_graph'
      js.add_client 'test2', url_href, 'empty_graph'
      clients = js.info_all_clients()

      client_list = Object.keys(clients)
      client_list.should.include 'test'
      client_list.should.include 'test2'

      for k in ['test', 'test2']
        ainfo = clients[k].mappings[0]
        ainfo.mbean.should.equal 'java.lang:somegroup'
        ainfo.attributes.length.should.equal 1
        ainfo.attributes[0].name.should.equal 'someattr'
        Object.keys(ainfo.attributes[0].graph).length.should.equal 0
      done()

  it "should be able to convert mappings to a hash", (done) =>
    js.load_all_templates () =>
      url_href = 'http://localhost:1234/jolokia/'
      js.add_client 'test', url_href, 'two_attribs'
      client = js.info_client('test')

      js.convert_mappings_to_hash client.mappings, (err, results) =>
        r = results['java.lang:name=ConcurrentMarkSweep,type=GarbageCollector']
        Object.keys(r).should.have.length 2
        for item in Object.keys(r)
          if item == 'CollectionCount'
            Object.keys(r[item]).should.have.length 1
            Object.keys(r[item]).should.include 'graph'
            Object.keys(r[item].graph).should.have.length 4
          else if item == 'LastGcInfo'
            Object.keys(r[item]).should.have.length 1
            Object.keys(r[item]).should
            .include 'memoryUsageBeforeGC|Code Cache|init'
            Object.keys(r[item]['memoryUsageBeforeGC|Code Cache|init']).should
            .include 'graph'
            Object.keys(r[item]['memoryUsageBeforeGC|Code Cache|init'].graph)
            .should.have.length 5
          else
            throw new Error("Should never get here")
        done()

  it "should be able to generate an intelligent jolokia query", (done) =>
    js.load_all_templates () =>
      url_href = 'http://localhost:1234/jolokia/'
      js.add_client 'test', url_href, 'two_mbeans'
      client = js.info_client('test')
      query_info = js.generate_query_info(client)
      query_info.should.have.length 2
      for q in query_info
        Object.keys(q).should.include('mbean')
        Object.keys(q).should.include('attribute')
        if q.composites.length > 0
          q.mbean.should.equal 'java.lang:type=Memory'
          q.attribute.should.equal 'HeapMemoryUsage'
          q.composites[0].name.should.equal 'init'
          q.composites[0].graph.name.should.equal 'Heap_init'
          q.composites[0].graph.type.should.equal 'int32'
        else
          q.mbean.should.equal \
            'java.lang:name=ConcurrentMarkSweep,type=GarbageCollector'
          q.attribute.should.equal 'CollectionCount'
          q.graph.name.should.equal 'GC_Collection_Count'
          q.graph.type.should.equal 'int32'
      done()

  # it "should be able to query a basic jolokia mbean", (done) =>
  #   post_data = () =>
  #     url_href = 'http://localhost:47432/jolokia/'
  #     js.add_client 'test', url_href
  #     , [
  #       { mbean: 'java.lang:name=ConcurrentMarkSweep,type=GarbageCollector',
  #       attributes: [
  #         { name: 'CollectionCount'
  #         graph:
  #           name: "GC_Collection_Count"
  #           description: "GC Collection Count"
  #           units: "gc count"
  #           type: "int32" }
  #       ] }
  #     ]

  #     js.query_jolokia 'test', (err, resp) =>
  #       Object.keys(resp).should
  #       .include 'java.lang:name=ConcurrentMarkSweep,type=GarbageCollector'
  #       k = resp['java.lang:name=ConcurrentMarkSweep,type=GarbageCollector']
  #       Object.keys(k).should.include 'CollectionCount'
  #       k['CollectionCount'].value.should.equal 46060
  #       Object.keys(k['CollectionCount'].graph).should.have.length 4
  #       srv.close()
  #       done()

  #   app = express()
  #   app.use express.bodyParser()
  #   app.post '/jolokia', (req, res, next) =>
  #     return_package = [
  #       { value: 46060
  #       request:
  #         type: 'read'
  #         mbean: 'java.lang:name=ConcurrentMarkSweep,type=GarbageCollector'
  #         attribute: 'CollectionCount'
  #       timestamp: 1356650995
  #       status: 200 }
  #     ]
  #     res.json 200, return_package

  #   srv = http.createServer(app)
  #   srv.listen(47432, post_data)

  # it "should be able to query a composite jolokia mbean", (done) =>
  #   post_data = () =>
  #     url_href = 'http://localhost:47432/jolokia/'
  #     js.add_client 'test', url_href
  #     , [
  #       { mbean: 'java.lang:type=Memory',
  #       attributes: [
  #         { name: 'HeapMemoryUsage'
  #         composites: [
  #           { name: 'init',
  #           graph:
  #             name: "Heap_init"
  #             description: "Initial Heap Memory Usage"
  #             units: "bytes"
  #             type: "int32" }
  #         ] }
  #       ] }
  #     ]
      
  #     js.query_jolokia 'test', (err, resp) =>
  #       Object.keys(resp).should.include 'java.lang:type=Memory'
  #       k = resp['java.lang:type=Memory']
  #       Object.keys(k).should.include 'HeapMemoryUsage'
  #       Object.keys(k['HeapMemoryUsage']).should.include 'init'
  #       k['HeapMemoryUsage']['init'].value.should.equal 393561088
  #       Object.keys(k['HeapMemoryUsage']['init'].graph).should.have.length 4
  #       srv.close()
  #       done()

  #   app = express()
  #   app.use express.bodyParser()
  #   app.post '/jolokia', (req, res, next) =>
  #     return_package = [
  #       { status: 200
  #       timestamp: 1357339120
  #       request:
  #         attribute: 'HeapMemoryUsage'
  #         type: 'read'
  #         mbean: 'java.lang:type=Memory'
  #       value:
  #         used: 257367360
  #         init: 393561088
  #         max: 2602041344
  #         committed: 2602041344 }
  #     ]
  #     res.json 200, return_package

  #   srv = http.createServer(app)
  #   srv.listen(47432, post_data)

  # it "should be able to query a multilevel composite jolokia mbean", (done) =>
  #   post_data = () =>
  #     url_href = 'http://localhost:47432/jolokia/'
  #     js.add_client 'test', url_href
  #     , [
  #       { mbean: 'java.lang:name=ParNew,type=GarbageCollector',
  #       attributes: [
  #         { name: 'LastGcInfo'
  #         composites: [
  #           { name: 'memoryUsageBeforeGc|Code Cache|init',
  #           graph:
  #             name: "MemoryUsage_Before_GC_Code_Cache_Init"
  #             description: "Code Cache (Init) Memory Usage Before GC"
  #             units: "bytes"
  #             type: "int32" },
  #           { name: 'memoryUsageBeforeGc|Code Cache|committed',
  #           graph:
  #             name: "MemoryUsage_Before_GC_Code_Cache_Committed"
  #             description: "Code Cache (Committed) Memory Usage Before GC"
  #             units: "bytes"
  #             type: "int32" }
  #         ] }
  #       ] }
  #     ]

  #     js.query_jolokia 'test', (err, resp) =>
  #       Object.keys(resp).should
  #       .include 'java.lang:name=ParNew,type=GarbageCollector'
  #       k = resp['java.lang:name=ParNew,type=GarbageCollector']
  #       Object.keys(k).should.include 'LastGcInfo'
  #       Object.keys(k['LastGcInfo']).should
  #       .include 'memoryUsageBeforeGc|Code Cache|init'
  #       k2 = k['LastGcInfo']['memoryUsageBeforeGc|Code Cache|init']
  #       k2.value.should.equal 2555904
  #       k3 = k['LastGcInfo']['memoryUsageBeforeGc|Code Cache|committed']
  #       k3.value.should.equal 9764864
  #       Object.keys(k2.graph).should.have.length 4
  #       srv.close()
  #       done()

  #   app = express()
  #   app.use express.bodyParser()
  #   app.post '/jolokia', (req, res, next) =>
  #     return_package = [
  #       { status: 200
  #       timestamp: 1356657870
  #       duration: 10
  #       request:
  #         attribute: 'LastGcInfo'
  #         type: 'read'
  #         mbean: 'java.lang:name=ParNew,type=GarbageCollector'
  #       value:
  #         id: 118583
  #         memoryUsageBeforeGc: 
  #           'Code Cache': 
  #             init: 2555904
  #             committed: 9764864
  #             used: 9589824
  #             max: 50331648
  #           'CMS Perm Gen': 
  #             init: 21757952
  #             committed: 75091968
  #             used: 44995904
  #             max: 268435456
  #           'CMS Old Gen': 
  #             init: 262406144
  #             committed: 1973878784
  #             used: 1257080824
  #             max: 1973878784
  #           'Par Eden Space': 
  #             init: 104988672
  #             committed: 558432256
  #             used: 558432256
  #             max: 558432256
  #           'Par Survivor Space': 
  #             init: 13107200
  #             committed: 69730304
  #             used: 6333344
  #             max: 69730304
  #         GcThreadCount: 11,
  #         endTime: 521639692
  #         startTime: 521639682
  #         memoryUsageAfterGc: 
  #           'Code Cache': 
  #             init: 2555904
  #             committed: 9764864
  #             used: 9589824
  #             max: 50331648
  #           'CMS Perm Gen': 
  #             init: 21757952
  #             committed: 75091968
  #             used: 44995904
  #             max: 268435456
  #           'CMS Old Gen': 
  #             init: 262406144
  #             committed: 1973878784
  #             used: 1257559928
  #             max: 1973878784
  #           'Par Eden Space':
  #             init: 104988672
  #             committed: 558432256
  #             used: 0
  #             max: 558432256
  #           'Par Survivor Space': 
  #             init: 13107200
  #             committed: 69730304
  #             used: 8012272
  #             max: 69730304 }
  #     ]
  #     res.json 200, return_package

  #   srv = http.createServer(app)
  #   srv.listen(47432, post_data)

  # it "should support sending metrics to ganglia", (done) =>
  #   server = dgram.createSocket('udp4')
  #   url_href = 'http://localhost:47432/jolokia/'
  #   js.add_client 'test', url_href
  #   , [
  #     { mbean: 'java.lang:name=ParNew,type=GarbageCollector',
  #     attributes: [
  #       { name: 'LastGcInfo'
  #       composites: [
  #         { name: 'memoryUsageBeforeGc|Code Cache|init',
  #         graph:
  #           name: "MemoryUsage_Before_GC_Code_Cache_Init"
  #           description: "Code Cache (Init) Memory Usage Before GC"
  #           units: "bytes"
  #           type: "int32" },
  #         { name: 'memoryUsageBeforeGc|Code Cache|committed',
  #         graph:
  #           name: "MemoryUsage_Before_GC_Code_Cache_Committed"
  #           description: "Code Cache (Committed) Memory Usage Before GC"
  #           units: "bytes"
  #           type: "int32" }
  #       ] }
  #     ] }
  #   ]

  #   js.jclients['test'].cache =
  #     'java.lang:name=ParNew,type=GarbageCollector':
  #       LastGcInfo: 
  #         'memoryUsageBeforeGc|Code Cache|init': 
  #           value: 2555904
  #           graph:
  #             name: 'MemoryUsage_Before_GC_Code_Cache_Init'
  #             units: 'bytes'
  #             type: 'int32'
  #             description: 'Code Cache (Init) Memory Usage Before GC'

  #         'memoryUsageBeforeGc|Code Cache|committed': 
  #           value: 9764864
  #           graph:
  #             name: 'MemoryUsage_Before_GC_Code_Cache_Committed'
  #             units: 'bytes'
  #             type: 'int32'
  #             description: 'Code Cache (Committed) Memory Usage Before GC'

  #   server.on 'message', (msg, rinfo) =>
  #     console.log msg

  #   server.on 'listening', () =>
  #     js.submit_metrics()
  #     setTimeout () =>
  #       server.close()
  #     , 10

  #   server.on 'close', () =>
  #     done()

  #   server.bind(43278)

  # it "should support templating for metric aggregation"

  # it "should support compound templates"

  # it "should have sane default graph configurations"
