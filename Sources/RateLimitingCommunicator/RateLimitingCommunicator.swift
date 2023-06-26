public var versionOfRLCommunicator = 0.1
import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


public actor RLCommunicator{
	//MARK: Initializers
	public init(minDelayInMillies: Double){
		self.minDelayInMillies = minDelayInMillies
		self.minDelayDuration = .milliseconds(minDelayInMillies)
	}
	public init(minDelay: Duration){
		self.minDelayDuration = minDelay
		self.minDelayInMillies = minDelay.totalMillies()
	}
	//MARK: Properties
	private let nanoOffset: DispatchTime = .now()
	static let name = "Rate Limiting Communicator"
	let minDelayInMillies: Double
	let minDelayDuration: Duration
	static public var isVerbose = false
    private var lastScheduledAt: DispatchTime?
    private var delayBeforeSendingNewRequest: Duration?{
        guard let lastScheduledAt else {
            return nil
        }
		if Self.isVerbose{
			print("lastScehduled at: "+timeStringWithMillies(date: lastScheduledAt, withNanoOffset: nanoOffset.uptimeNanoseconds))
		}
		if lastScheduledAt >= .now(){
			let newDate = lastScheduledAt.advanced(by: .duration(d: minDelayDuration))
			let delay = DispatchTime.now().distance(to: newDate)
			return .dispatchTimeInterval(delay)
        }else{
			let distanceToNow = lastScheduledAt.distance(to: .now())
			let durationToNow:Duration = .dispatchTimeInterval(distanceToNow)
			let delayOffsetDuration: Duration = minDelayDuration - durationToNow
			let lastScheduleAffectsUs = delayOffsetDuration > .zero
			return lastScheduleAffectsUs ? delayOffsetDuration : nil
        }
    }
	struct ScheduledPayload{
		var lastUpdated: Date
		var method: () async throws->Any
	}
	private var toBeSent = [String: ScheduledPayload]()
	private func getPayloadForRequest<R>(for payload: R?)->(()async throws-> Any)?{
		guard let payload=payload as? (any PayloadType) else {return nil}
		let payloadID = payload.id as? String ?? "\(payload.id)"
		return toBeSent[payloadID]?.method
	}
	private func notePayloadRequest<R:Identifiable&LastUpdated>(for payload: R, method: @escaping ()async throws-> Any){
		let payloadID = payload.id as? String ?? "\(payload.id)"
		let payloadDate = payload.lastUpdatedDate
		guard let current = toBeSent[payloadID] else {toBeSent[payloadID] = .init(lastUpdated: payloadDate, method: method);return}
		guard payloadDate > current.lastUpdated else {
			//item is older, ignore
			return
		}
		toBeSent[payloadID]!.lastUpdated=payloadDate
		toBeSent[payloadID]!.method=method
	}
	//MARK: Public
	typealias PayloadType = Identifiable&LastUpdated
	@discardableResult
	public func sendRequest<R, T>(payload: R?, _ request: @escaping () async throws->T)async throws->T{
		if let payload = payload as? (any PayloadType){
			notePayloadRequest(for: payload, method: request)
		}
		let myID = UUID().uuidString.prefix(2)
		if Self.isVerbose{
			printWithTimeInfoAsync("Called to send request <\(myID)>", withNanoOffset: nanoOffset.uptimeNanoseconds)
		}
		guard let delay = delayBeforeSendingNewRequest else{
			if Self.isVerbose{
				printWithTimeInfoAsync("No delay, doing now request <\(myID)>", withNanoOffset: nanoOffset.uptimeNanoseconds)
			}
			lastScheduledAt = .now()
			let method = getPayloadForRequest(for: payload) ?? request
			return try await method() as! T
		}
		lastScheduledAt = .now().advanced(by: .duration(d: delay))
		#if !os(Linux)
		if Self.isVerbose{
			printWithTimeInfoAsync("Will wait \(delay.formatted(tmf)) for <\(myID)>", withNanoOffset: nanoOffset.uptimeNanoseconds)
		}
		#endif
		try await Task.sleep(for: delay)
		let method = getPayloadForRequest(for: payload) ?? request
		return try await method() as! T
	}
	@discardableResult
	public func sendRequest<T>(_ request: @escaping () async throws->T)async throws->T{
		return try await sendRequest(payload: Optional<ShellLastUpdated>.none, request)
	}

	@inlinable
	func printWithTimeInfoAsync(_ message: String, withNanoOffset nanoOffset: UInt64){
		let n: DispatchTime = .now()
		Task{
			print("[\(timeStringWithMillies(date: n, withNanoOffset: nanoOffset))] "+message)
		}
	}
	
	
	
	@inlinable
	func timeStringWithMillies(date: DispatchTime, withNanoOffset nanoOffset: UInt64)->String{
		let ns = date.uptimeNanoseconds-nanoOffset
		let minutes = ns / 60_000_000_000
		let leftovers = ns % 60_000_000_000
		let seconds = leftovers / 1_000_000_000
		let	nsLeft = leftovers % 1_000_000_000
		let msLeft = nsLeft / 1_000_000
		let totalLeftOvers = nsLeft % 1_000_000
		return "\(minutes):\(seconds).\(msLeft).\(totalLeftOvers)"
	}
	
	@inlinable
	func currentTimeStringWithMillies(withNanoOffset nanoOffset: UInt64)->String{
		timeStringWithMillies(date: .now(), withNanoOffset: nanoOffset)
	}
}
//MARK: General/Extensions
public protocol LastUpdated{
	var lastUpdatedDate: Date { get }
}
struct ShellLastUpdated: LastUpdated, Identifiable{
	var lastUpdatedDate: Date = .now
	var id: String = UUID().uuidString
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
	func totalMillies()->Double{
		return Double(totalNanoSeconds()) / 1_000_000.0
	}
}
extension DispatchTimeInterval{
	static func duration(d duration: Duration)->Self{
		return .nanoseconds(duration.totalNanoSeconds())
	}
}
#if os(Linux)
extension Date{
	public static var now: Self{
		Date()
	}
}
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
