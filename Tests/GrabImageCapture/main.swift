import AppKit
func check(_ ok: Bool, _ name: String) { if !ok { fatalError(name) }; print("PASS: " + name) }
let jpeg = "https://i.pinimg.com/736x/ab/cd/test.jpg"
check(GrabImageCapture.candidates(html: "<img src='\(jpeg)'>", imageURL: "", page: "").first?.absoluteString == jpeg, "single-quoted Pinterest source is accepted without invented originals")
check(GrabImageCapture.candidates(html: "<img data-src='https://wrong.example/a.jpg' src=\(jpeg)>", imageURL: "", page: "").first?.absoluteString == jpeg, "unquoted source does not match data-src")
let ranked = GrabImageCapture.candidates(html: "<img srcset='small.jpg 1x, large.jpg 2x' src='fallback.jpg'>", imageURL: "", page: "https://example.com/pins/")
check(ranked.map { $0.lastPathComponent } == ["large.jpg", "small.jpg", "fallback.jpg"], "srcset ranking and relative URLs")
check(GrabImageCapture.candidates(html: "<img src='https://example.com/a.jpg?x=1&amp;y=2'>", imageURL: "", page: "").first?.query == "x=1&y=2", "HTML entity decoding")
check(GrabImageCapture.imageAddress(jpeg), "URL-only Pinterest image recognised")
check(!GrabImageCapture.imageAddress("https://www.pinterest.com/pin/123/"), "ordinary copied pin links are not images")
check(GrabImageCapture.candidates(html: "<img src='javascript:alert(1)'>",imageURL:"file:///etc/passwd",page:"").isEmpty,"non-web schemes rejected")
let pb = NSPasteboard.withUniqueName()
defer { pb.releaseGlobally() }
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:3,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
for (type, format) in [("public.png",NSBitmapImageRep.FileType.png),("public.jpeg",.jpeg),("public.tiff",.tiff)] {
 let fixture=bitmap.representation(using:format,properties:[:])!
 check(GrabImageCapture.size(fixture)?.0 == 3, "fixture decoded")
 pb.clearContents()
 if pb.setData(fixture,forType:.init(type)), pb.data(forType:.init(type)) != nil {
  let got=GrabImageCapture.clipboardImage(pb)
  check(got.flatMap { GrabImageCapture.size($0) }?.0 == 3,"clipboard \(type) decoded")
 } else { print("SKIP: pasteboard service unavailable in terminal sandbox (\(type)); image fixture decoding passed") }
}
pb.clearContents(); pb.setString("ordinary text",forType:.string)
check(GrabImageCapture.clipboardImage(pb)==nil,"plain text is not an image")

final class CaptureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "needed-capture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path == "/slow" { return }
        let status = request.url!.path == "/missing" ? 404 : 200
        let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("fixture".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
URLProtocol.registerClass(CaptureProtocol.self)
check(GrabImageCapture.download(URL(string:"https://needed-capture.test/image")!,page:"",timeout:1)==Data("fixture".utf8),"URL-only download succeeds")
check(GrabImageCapture.download(URL(string:"https://needed-capture.test/missing")!,page:"",timeout:1)==nil,"404 download rejected")
let start=Date()
check(GrabImageCapture.download(URL(string:"https://needed-capture.test/slow")!,page:"",timeout:0.15)==nil,"stalled request times out")
check(Date().timeIntervalSince(start)<1,"stalled request has bounded wait")
URLProtocol.unregisterClass(CaptureProtocol.self)
