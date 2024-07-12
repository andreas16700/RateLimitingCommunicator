import XCTest
import Dispatch

@testable import RateLimitingCommunicator

final class RateLimitingCommunicatorTests: XCTestCase {
    func testRapidUpdating()async throws{
        struct Payload{
            var n: String = ""
            var num: Int = 0
            var str: String{
                "\(n) \(num)"
            }
        }
        let rl = RateLimitterWithUpdating<Payload>(sendOp: {
            print("Sent \($0.str)")
        })
        var p = Payload()
        var prev = Date.now
        for i in 0..<50{
            let d = Date.now
            XCTAssertTrue(prev<d)
            await rl.add(p, d)
            p.n+="\(i)"
            p.num+=i
            prev = d
        }
        try await Task.sleep(for: .seconds(20))
    }
    func testLeastNumRemAfterKInts(){
        class Solution {
            func findLeastNumOfUniqueInts(_ arr: [Int], _ k: Int) -> Int {
                let apps = arr.reduce(into: [Int: Int]()){d, n in
                    d[n, default: 0]+=1
                }
                let keys = apps.keys.sorted(by: {apps[$0]!<apps[$1]!})
                var sum = 0
                var i = 0
                while sum<k{
                    var newNums = apps[keys[i]]!
                    let difference = k-sum
                    if newNums>difference{
                        break
                    }
                    sum += newNums
                    i+=1
                }
                return keys.count - i
            }
        }
        let n = Solution().findLeastNumOfUniqueInts([5,5,5,4], 1)
        XCTAssertEqual(n, 1)
        
        let n2 = Solution().findLeastNumOfUniqueInts([4,3,1,1,3,3,2], 3)
        XCTAssertEqual(n2, 2)
        /**
         
         
         
         2  x
         4  x
         1  xx
         3  xxx
         
         
         
         */
    }
    func testElse(){
        class Solution {
            func findMedianSortedArrays(_ nums1: [Int], _ nums2: [Int]) -> Double {
                let mergedSize = nums1.count + nums2.count
                var elementIndices: [Int]
                var medianElements = [Int]()
                if mergedSize % 2 == 1{
                    elementIndices = [mergedSize/2]
                }else{
                    elementIndices = [mergedSize/2, ((mergedSize/2) - 1)]
                }
                var i1=0
                var i2=0
                
                var considerOnlyTwo=false
                
                for i in 0..<mergedSize{
                    let currentNum: Int
                    if considerOnlyTwo || nums1[i1] < nums2[i2]{
                        currentNum = nums1[i1]
                        if i1+1 < nums1.count{
                            i1+=1
                        }else{
                            considerOnlyTwo=true
                        }
                    }else{
                        currentNum = nums2[i2]
                        i2+=1
                    }
                    if elementIndices.contains(i){
                        medianElements.append(currentNum)
                        if elementIndices.count == medianElements.count{
                            break
                        }
                    }
                }
                return Double(medianElements.reduce(0, +))/Double(elementIndices.count)
            }
        }
        let s = Solution().findMedianSortedArrays([1,2], [3,4])
        print("\(s)")
    }
    
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
