import Foundation

// 自定义字段（field）和元素（element）必须以下划线开头
// http://www.softwareishard.com/blog/har-12-spec/
class HAR: Codable {
    var log: Log
    init() { self.log = Log() }
}

class Log: Codable {
    
    var version: String = "1.2" // 版本，默认为1.1
    var creator: Creator        // 创建HAR文件的程序名称和版本信息
    var browser: Browser?       // 浏览器的名称和版本信息
    var pages:[Page]?           // 页面列表，如果应用不支持按照page分组，可以省去此字段
    var entries:[Entry]         // 所有HTTP请求的列表
    var comment:String?         // 注释
    
    init() {
        self.creator = Creator(name: "Knot", version: "1.0", comment: nil)
        self.entries = [Entry]()
    }
}

typealias Browser = Creator

class Creator: Codable {
    var name: String        //HAR生成工具或者浏览器的名称
    var version: String     //HAR生成工具或者浏览器的版本
    var comment: String?    //注释
    
    init(name:String = "Knot",version:String = "1.0",comment:String? = nil) {
        self.name = name
        self.version = version
        self.comment = comment
    }
}

class Page: Codable {
    // 页面开始加载的时间(格式ISO 8601 – YYYY-MM-DDThh:mm:ss.sTZD, 例如2009-07-24T19:20:30.45+01:00)
    var startedDateTime: String
    // "page_0", page的唯一标示，entry会用到这个id来和page关联在一起
    var id: String
    // "Test Page", 页面标题
    var title: String
    //页面加载过程中详细的时间信息
    var pageTimings: [PageTiming]
    var comment: String?
    init(startedDateTime:String,id:String,title:String,pageTimings:[PageTiming],comment:String?) {
        self.startedDateTime = startedDateTime
        self.id = id
        self.title = title
        self.pageTimings = pageTimings
        self.comment = comment
    }
}

class PageTiming: Codable {
    // 页面内容加载时间，相对于页面开始加载时间的毫秒数（page.startedDateTime）。如果时间不适用于当前的请求，那么置为-1。
    var onContentLoad: Int?
    // 页面加载时间（即onLoad事件触发的时间）。相对于页面开始加载时间的毫秒数（page.startedDateTime）。如果时间不适用于当前的请求，那么置为-1。
    var onLoad: Int?
    var comment: String?
}

class Entry: Codable {
    //页面id，如果不支持按照page分组，那么字段为空
    var pageref: String?
    // 请求开始时间 (格式ISO 8601 – YYYY-MM-DDThh:mm:ss.sTZD)。
    var startedDateTime: String
    // 请求消耗的时间，以毫秒为单位。这个值是timings对象中所有可用(值不为-1) timing的和。
    var time: Int
    // 请求的详细信息。
    var request: Request
    // 响应的详细信息。
    var response: Response
    // 缓存使用情况的信息。
    var cache: Cache
    // 请求/响应过程（round trip）的详细时间信息。
    var timings: Timings
    // 服务器IP地址。
    var serverIPAddress: String
    // TCP/IP连接的唯一标示。 如果程序不支持，直接忽略此字段。
    var connection: String?
    var comment: String?
 
    init(startedDateTime: String, time:Int, request: Request, response: Response, cache: Cache, timings: Timings, serverIPAddress: String) {
        self.startedDateTime = startedDateTime
        self.time = time
        self.request = request
        self.response = response
        self.cache = cache
        self.timings = timings
        self.serverIPAddress = serverIPAddress
    }
}

class Request: Codable {
    // "GET", [string] – 请求方法(GET，POST，...)。
    var method: String
    // "http://www.example.com/path/?param=value", [string] – 请求的绝对URL(fragments are not included)。
    var url: String
    // "HTTP/1.1",请求HTTP版本。
    var httpVersion: String
    // cookie列表。
    var cookies: [Cookie]
    // header列表。
    var headers: [Header]
    // 查询字符串信息。
    var queryString: [QueryString]
    // Post数据信息。
    var postData:PostData?
    // HTTP请求头的字节数。如果不可用，设置为-1。
    var headersSize: Int
    // 请求body字节数（POST数据）。如果不可用，设置为-1。
    var bodySize: Int
    var comment: String?
    
    init(method: String,url: String,httpVersion: String,cookies: [Cookie],
         headers: [Header],queryString: [QueryString],headersSize: Int,bodySize: Int) {
        self.method = method
        self.url = url
        self.httpVersion = httpVersion
        self.cookies = cookies
        self.headers = headers
        self.queryString = queryString
        self.headersSize = headersSize
        self.bodySize = bodySize
    }
}

class Response: Codable {
    
    // 响应状态 200
    var status: Int?
    // 响应状态描述 "OK"
    var statusText: String?
    // HTTP版本 "HTTP/1.1"
    var httpVersion: String?
    // cookie列表
    var cookies: [Cookie]?
    // header列表
    var headers: [Header]?
    // 响应内容的详细信息
    var content: Content?
    // Location响应头中的重定向URL
    var redirectURL: String?
    // HTTP请求头的字节数。如果不可用，设置为-1
    // 注：headersSize – 响应头大小只对从服务器接收到的header进行计算。被浏览器加上的header不计算在内，但是会加在header列表中。
    var headersSize: Int?
    // 接收的body字节数。如果响应来自缓存(304)，那么设置为0。如果不可用，设置为-1
    var bodySize: Int?
    var comment: String?
    
    init(status: Int,statusText: String,httpVersion: String,
         cookies: [Cookie],headers: [Header],content: Content,
         redirectURL: String,headersSize: Int,bodySize: Int) {
        self.status = status
        self.statusText = statusText
        self.httpVersion = httpVersion
        self.cookies = cookies
        self.headers = headers
        self.content = content
        self.redirectURL = redirectURL
        self.headersSize = headersSize
        self.bodySize = bodySize
    }
    
    init() {
        
    }
}

class Cookie: Codable {
    // cookie名称 "TestCookie",
    var name: String
    // cookie值 "Cookie Value",
    var value: String
    // cookie Path "/",
    var path: String?
    // cookie域名 "www.janodvarko.cz",
    var domain: String?
    // cookie过期时间(格式ISO 8601  YYYY-MM-DDThh:mm:ss.sTZD, 例如2009-07-24T19:20:30.123+02:00)
    var expires: String?
    // 如果cookie只是在HTTP下有效，此值设置为true，否则设置为false
    var httpOnly: Bool?
    // 如果cookie通过ssl传送，此值设置为true，否则设置为false
    var secure: Bool?

    var maxAge: Int?
    var sameSite: String?
    // 注释
    var comment: String?
    
    init(name: String,value: String) {
        self.name = name
        self.value = value
    }
}

typealias QueryString = Header

class Header: Codable {
    var name:String
    var value:String
    var comment:String?
    init(name:String,value:String) {
        self.name = name
        self.value = value
    }
}

class PostData: Codable {
    
    // POST数据的MIME类型  "multipart/form-data"
    var mimeType: String
    // POST参数列表 (in case of URL encoded parameters)
    var params: [Param]?
    // POST数据的纯文本形式(Plain text posted data)
    var text: String?
    var comment: String?
    // 注意：text和params字段是互斥的。
    init(mimeType: String,params: [Param]?,text: String?) {
        self.mimeType = mimeType
        self.params = params
        self.text = text
    }
}

class Param: Codable {
    // POST参数名
    var name: String
    // POST参数的值，或者POST文件的内容
    var value: String?
    // POST文件的文件名 "example.pdf"
    var fileName: String?
    // POST文件的类型 "application/pdf"
    var contentType: String?
    // 注释
    var comment: String?
    
    init(name:String) {
        self.name = name
    }
}

class Content: Codable {
    
    // 返回内容的字节数。如果内容没有被压缩，应该和response.bodySize相等；如果被压缩，那么会大于response.bodySize
    var size: Int
    // 节省的字节数。如果无法提供此信息，则忽略此字段
    var compression: Int?
    // 响应文本的MIME类型 (Content-Type响应头的值)。MIMIE类型的字符集也包含在内  "text/html; charset="utf-8"
    var mimeType: String
    // 从服务器返回的响应body或者从浏览器缓存加载的内容。这个字段只能用文本型的内容来填充。字段内容可以是HTTP decoded(decompressed & unchunked)的文本，或者是经编码（例如，base64）过的响应内容。如果信息不可用，忽略此字段
    var text: String?
    // 响应内容的编码格式，例如”base64″。如果text字段的内容是经过了HTTP解码(decompressed & unchunked)的，那么忽略此字段
    var encoding: String?
    // 注释
    var comment: String?
    
    init(size:Int, mimeType: String) {
        self.size = size
        self.mimeType = mimeType
    }

}

class Cache: Codable {
    var beforeRequest: BeforeRequest? // 在请求之前缓存的状态。如果信息不可用，可以忽略此字段。
    var afterRequest: AfterRequest? // 在请求之后缓存的状态。 如果信息不可用，可以忽略此字段。
    var comment: String?
}

typealias AfterRequest = BeforeRequest

class BeforeRequest: Codable {
    
    // 缓存过期时间
    var expires: String?
    // 缓存最后被访问的时间
    var lastAccess: String
    // Etag
    var eTag: String
    // 缓存被访问的次数
    var hitCount: Int
    var comment: String?
    init(lastAccess: String,eTag: String,hitCount: Int) {
        self.lastAccess = lastAccess
        self.eTag = eTag
        self.hitCount = hitCount
    }
}

class Timings: Codable {
    
    // 建立网络连接时在队列里边等待的时间。如果时间对于当前请求不可用，置为-1。
    var blocked: Int?
    // DNS查询时间。如果时间对于当前请求不可用，置为-1。
    var dns: Int?
    // 建立TCP连接所需的时间。如果时间对于当前请求不可用，置为-1。
    var connect: Int?
    // 发送HTTP请求到服务器所需的时间。
    var send: Int
    // 等待服务器返回响应的时间。
    var wait: Int
    // 接收服务器响应（或者缓存）所需时间。
    var receive: Int
    // SSL/TLS验证花费时间。如果这个字段被定义了，那么这个时间也会被包含进connect字段中(为了向后兼容HAR1.1)。如果时间对于当前请求不可用，置为-1。
    var ssl: Int?
    var comment: String?
    init(send: Int, wait: Int, receive: Int) {
        self.send = send
        self.wait = wait
        self.receive = receive
    }
}
