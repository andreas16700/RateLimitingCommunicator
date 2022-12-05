import XCTest
@testable import RateLimittingCommunicator

final class RateLimittingCommunicatorTests: XCTestCase {
	static let acceptableMillisecondMargin = 100.0
	static let accetableAverage = 60.0
	func checkCatalogue(_ cat: TaskCompletionCatalogue)async{
		let ascending = await cat.sortedTimeAscending()
		for i in 0..<ascending.count-1{
			let current = ascending[i]
			let nextOne = ascending[i+1]
			XCTAssertTrue(TaskCompletionCatalogue.pairIsAcceptable(current, nextOne, millieUpMargin: Self.acceptableMillisecondMargin))
		}
		let allOffs = await cat.allOffsetsInMillies()
		let avg = allOffs.avg()
		XCTAssertTrue(avg <= Self.accetableAverage)
		let stddev = allOffs.std()
		print("Average: \(avg)\tStd Dev: \(stddev)")
	}
	
    func testSendMultiple() async throws {
		let totalRequestCount = 50
		let catalogue = TaskCompletionCatalogue()
		let rl = RLCommunicator.shared
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
				try await Task.sleep(for: .milliseconds(200))
			}
			for task in tasks {
				let _ = try await task.value
			}
		}
        try await sendAllRequestsAndWait(count: totalRequestCount)
		await checkCatalogue(catalogue)
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
	static func offsetInMilliesFromIntentedDelay(_ lhs: DispatchTime, _ rhs: DispatchTime)->Double{
		let intentedDelayInNanos = RLCommunicator.minDelayInMillies * 1_000_000
		let differenceInNanos = Int64(rhs.uptimeNanoseconds - lhs.uptimeNanoseconds) - Int64(intentedDelayInNanos)
		
		let differenceInMillies = Double(differenceInNanos)/1_000_000.0
		return differenceInMillies
	}
	static func pairIsAcceptable(_ lhs: IDWithTime, _ rhs: IDWithTime, millieUpMargin: Double)->Bool{
		let differenceInMillies = offsetInMilliesFromIntentedDelay(lhs.1, rhs.1)
		print("[\(lhs.0)]->[\(rhs.0)] delay+(\(differenceInMillies))ms")
		
		return abs(differenceInMillies) <= millieUpMargin
	}
	func allOffsetsInMillies(absoluteValues: Bool = true)->[Double]{
		let sorted = sortedTimeAscending()
		let indices = Array(0..<sorted.count-1)
		
		return indices.map{i in
			let lhs = sorted[i].1
			let rhs = sorted[i+1].1
			let offset = Self.offsetInMilliesFromIntentedDelay(lhs, rhs)
			return absoluteValues ? abs(offset) : offset
		}
	}
}
