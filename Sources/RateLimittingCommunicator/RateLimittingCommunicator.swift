import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


actor RLCommunicator{
    static let name = "Rate Limiting Communicator"
    static let minDelayInMillies = 600
	static let minDelayDuration: Duration = .milliseconds(minDelayInMillies)
    static let shared = RLCommunicator()

    private init(){}
    private var lastScheduledAt: DispatchTime?
    private var delayBeforeSendingNewRequest: Duration?{
        guard let lastScheduledAt else {
            return nil
        }
		#if DEBUG
		print("lastScehduled at: "+timeStringWithMillies(date: lastScheduledAt))
		#endif
		if lastScheduledAt >= .now(){
			let newDate = lastScheduledAt.advanced(by: .milliseconds(Self.minDelayInMillies))
			let delay = DispatchTime.now().distance(to: newDate)
			return .dispatchTimeInterval(delay)
        }else{
			let distanceToNow = lastScheduledAt.distance(to: .now())
			let durationToNow:Duration = .dispatchTimeInterval(distanceToNow)
			let delayOffsetDuration: Duration = Self.minDelayDuration - durationToNow
			let lastScheduleAffectsUs = delayOffsetDuration > .zero
			return lastScheduleAffectsUs ? delayOffsetDuration : nil
        }
    }
	@discardableResult
	func sendRequest<T>(_ request: () async throws->T)async throws->T{
		#if DEBUG
		let myID = UUID().uuidString.prefix(2)
		printWithTimeInfoAsync("Called to send request <\(myID)>")
		#endif
		guard let delay = delayBeforeSendingNewRequest else{
			#if DEBUG
			printWithTimeInfoAsync("No delay, doing now request <\(myID)>")
			#endif
            lastScheduledAt = .now()
            return try await request()
        }
		lastScheduledAt = .now().advanced(by: .duration(d: delay))
		#if DEBUG && !os(Linux)
		printWithTimeInfoAsync("Will wait \(delay.formatted(tmf)) for <\(myID)>")
		#endif
        try await Task.sleep(for: delay)
        return try await request()
	}

	@inlinable
	func printWithTimeInfoAsync(_ message: String){
		let n: DispatchTime = .now()
		Task{
			print("[\(timeStringWithMillies(date: n))] "+message)
		}
	}
	
	let nanoOffset: DispatchTime = .now()
	
	@inlinable
	func timeStringWithMillies(date: DispatchTime)->String{
		let ns = date.uptimeNanoseconds-nanoOffset.uptimeNanoseconds
		let minutes = ns / 60_000_000_000
		let leftovers = ns % 60_000_000_000
		let seconds = leftovers / 1_000_000_000
		let	nsLeft = leftovers % 1_000_000_000
		let msLeft = nsLeft / 1_000_000
		let totalLeftOvers = nsLeft % 1_000_000
		return "\(minutes):\(seconds).\(msLeft).\(totalLeftOvers)"
	}
	
	@inlinable
	func currentTimeStringWithMillies()->String{
		timeStringWithMillies(date: .now())
	}
}
#if !os(Linux)
let tmf = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 6, roundFractionalSeconds: .toNearestOrEven))
#endif
extension Duration{
	static func dispatchTimeInterval(_ dispatchTimeInterval: DispatchTimeInterval)->Self{
		switch dispatchTimeInterval {
		case .seconds(let int):
			return .seconds(int)
		case .milliseconds(let int):
			return .milliseconds(int)
		case .microseconds(let int):
			return .microseconds(int)
		case .nanoseconds(let int):
			return .nanoseconds(int)
		case .never:
			return .zero
		@unknown default:
			fatalError()
		}
	}
	func totalNanoSeconds()->Int{
		let attos = components.attoseconds
		let inNanoSeconds = attos / 1_000_000_000
		let nanosFromSecondsComponent = components.seconds * 1_000_000_000
		let totalInNanos = Int(inNanoSeconds+nanosFromSecondsComponent)
		return totalInNanos
	}
}
extension DispatchTimeInterval{
	static func duration(d duration: Duration)->Self{
		return .nanoseconds(duration.totalNanoSeconds())
	}
}
#if os(Linux)
extension DispatchTime{
	func advanced(by ti: DispatchTimeInterval)->Self{
		let base = self.uptimeNanoseconds
		let multiplier: Int
		let value: Int
		switch ti {
		case .seconds(let int):
			multiplier = 1_000_000_000;value=int
		case .milliseconds(let int):
			multiplier = 1_000_000;value=int
		case .microseconds(let int):
			multiplier = 1_000;value=int
		case .nanoseconds(let int):
			multiplier = 1;value=int
		case .never:
			multiplier=0;value=0
		@unknown default:
			fatalError()
		}
		let nanoSecsToAdd = value*multiplier
		let newBase = base+UInt64(nanoSecsToAdd)
		return .init(uptimeNanoseconds: newBase)
	}
	func distance(to later: DispatchTime)->DispatchTimeInterval{
		let nanoDiff = later.uptimeNanoseconds - uptimeNanoseconds
		return .nanoseconds(Int(nanoDiff))
	}
}
#endif
