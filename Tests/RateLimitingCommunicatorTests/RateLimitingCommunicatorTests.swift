import XCTest
import Dispatch

@testable import RateLimitingCommunicator

final class RateLimitingCommunicatorTests: XCTestCase {
    
    
    func testNew()async throws{
        
        
        let rl = RateLimitterWithUpdating<String>(sendOp: {
            try! await Task.sleep(for: .seconds(1))
            print("[simulated sent for \($0)]")
        })
        
        
        let d = Date()
        let ti = 0.5
        
        let stuff = Array(0...15).map{i in
            let theDate = d.addingTimeInterval(ti*Double(i))
            return ("\(i)", theDate)
        }
        
        await withTaskGroup(of: Void.self, body: {g in
            stuff.shuffled().forEach{(p,date) in
                g.addTask {
//                    print("[\(p)] Begin")
                    await rl.add(p, date)
//                    print("[\(p)] End")
                }
            }
        })
        
        
        
    }
    
	/**
	 How many ms it's acceptable for requests to deviate from the intented delay.
	 For example:
	 We set the delay to 500ms meaning a request should be sent at least 500ms after the previous one
	 RateLimitingCommunicator does its best  to achieve that but in some cases two requests sent consecutively could sent with a delay between them of 503ms or 497ms instead of the intented 500ms. This ± here is the acceptableMillisecondMargin.
	 */
	static let acceptableMillisecondMargin = 100.0
	/**
	 In testing, mutliple requests are sent (each is sent without waiting for the previous one to finish) and in the end, the actual time difference between them is measured and the average is taken. This variable sets the acceptable average deviation from the intented delay (in milliseconds).
	 */
	static let accetableMilliesOffsetAverage = 60.0
	func checkCatalogue(_ cat: TaskCompletionCatalogue, intendedDelay: Duration)async{
		let ascending = await cat.sortedTimeAscending()
		for i in 0..<ascending.count-1{
			let current = ascending[i]
			let nextOne = ascending[i+1]
			XCTAssertTrue(TaskCompletionCatalogue.pairIsAcceptable(current, nextOne, millieUpMargin: Self.acceptableMillisecondMargin, intendedDelay: intendedDelay))
		}
		let allOffs = await cat.allOffsetsInMillies(intendedDelay: intendedDelay)
		let avg = allOffs.avg()
		XCTAssertTrue(avg <= Self.accetableMilliesOffsetAverage)
		let stddev = allOffs.std()
		print("Average: \(avg)\tStd Dev: \(stddev)")
	}
	
	func testSendMultiple(withDelay delay: Duration, requestCount totalRequestCount: Int) async throws {
		let catalogue = TaskCompletionCatalogue()
		let rl = RLCommunicator(minDelay: delay)
		@Sendable func receiveRequest(message: Int){
			let now: DispatchTime = .now()
			print("Received \(message)")
			catalogue.noteCompletedTask(of: message, at: now)
		}
		func sendAllRequestsAndWait(count: Int)async throws{
			
			var tasks = [Task<(),Error>]()
			for i in 0..<count{
				tasks.append(Task{
					print("Sending \(i)")
					try await rl.sendRequest {
						receiveRequest(message: i)
					}
				})
//				try await Task.sleep(for: .milliseconds(50))
			}
			for task in tasks {
				let _ = try await task.value
			}
		}
        try await sendAllRequestsAndWait(count: totalRequestCount)
		await checkCatalogue(catalogue, intendedDelay: delay)
    }
	func testSendMultipleDelay600ms() async throws {
		let delay: Duration = .milliseconds(600)
		try await testSendMultiple(withDelay: delay, requestCount: 50)
	}
	func testSendMultipleUpdatedVersions()async throws{
		struct Thing: LastUpdated, Identifiable, Equatable{
			var id: String = .init(UUID().uuidString.prefix(2))
			var lastUpdatedDate: Date = .now
			var storage = 1
			mutating func update(){
				storage+=1
				lastUpdatedDate = .now
			}
		}
		let rl = RLCommunicator(minDelayInMillies: 1000)
		@Sendable func receiveRequest(thing received: Thing)->Thing{
			print("Received \(received.storage)")
			return received
		}
		let stallCount = 1
		Array(0..<stallCount).forEach{_ in Task{let _ = try await rl.sendRequest({})}}
		var thing: Thing = .init()
		let updateCount = 10
		var tasks = [Task<Thing,Error>]()
		for _ in 0..<updateCount{
			thing.update()
			let myPayload = thing
			tasks.append(Task{
				
				print("Sending \(myPayload.storage)")
				return try await rl.sendRequest(payload: myPayload) {
					return receiveRequest(thing: myPayload)
				}
			})
//				try await Task.sleep(for: .milliseconds(50))
		}
		print("Latest version: \(thing.storage)")
		for task in tasks {
			let v = try await task.value
			XCTAssertEqual(v, thing)
		}
	}
}
extension Array where Element: FloatingPoint {

	func sum() -> Element {
		return self.reduce(0, +)
	}

	func avg() -> Element {
		return self.sum() / Element(self.count)
	}

	func std() -> Element {
		let mean = self.avg()
		let v = self.reduce(0, { $0 + ($1-mean)*($1-mean) })
		return sqrt(v / (Element(self.count) - 1))
	}

}
actor TaskCompletionCatalogue{
	typealias IDWithTime = (Int, DispatchTime)
	private var cat: [Int: DispatchTime] = .init()
	
	func _noteCompletedTask(of id: Int, at time: DispatchTime){
		cat[id]=time
	}
	
	nonisolated func noteCompletedTask(of id: Int, at time: DispatchTime){
		Task{
			await _noteCompletedTask(of: id, at: time)
		}
	}
	func sortedTimeAscending()->[IDWithTime]{
		return cat.sorted(by: {
			$0.value < $1.value
		})
	}
	static func offsetInMilliesFromIntentedDelay(_ lhs: DispatchTime, _ rhs: DispatchTime, intendedDelay: Duration)->Double{
		let intentedDelayInNanos = intendedDelay.totalNanoSeconds()
		let differenceInNanos = Int64(rhs.uptimeNanoseconds - lhs.uptimeNanoseconds) - Int64(intentedDelayInNanos)
		
		let differenceInMillies = Double(differenceInNanos)/1_000_000.0
		return differenceInMillies
	}
	static func pairIsAcceptable(_ lhs: IDWithTime, _ rhs: IDWithTime, millieUpMargin: Double, intendedDelay: Duration)->Bool{
		let differenceInMillies = offsetInMilliesFromIntentedDelay(lhs.1, rhs.1, intendedDelay: intendedDelay)
		print("[\(lhs.0)]->[\(rhs.0)] delay+(\(differenceInMillies))ms")
		
		return abs(differenceInMillies) <= millieUpMargin
	}
	func allOffsetsInMillies(absoluteValues: Bool = true, intendedDelay: Duration)->[Double]{
		let sorted = sortedTimeAscending()
		let indices = Array(0..<sorted.count-1)
		
		return indices.map{i in
			let lhs = sorted[i].1
			let rhs = sorted[i+1].1
			let offset = Self.offsetInMilliesFromIntentedDelay(lhs, rhs, intendedDelay: intendedDelay)
			return absoluteValues ? abs(offset) : offset
		}
	}
}
