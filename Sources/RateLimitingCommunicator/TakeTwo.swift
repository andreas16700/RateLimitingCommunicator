//
//  TakeTwo.swift
//  
//
//  Created by Andreas Loizides on 24/06/2024.
//

import Dispatch
import Foundation

actor _RL<Payload>{
    init(minDelay: Duration = .milliseconds(500), sendOperation: @escaping (Payload) async -> Void) {
        self.holder = .init(minDelay: minDelay, sendOperation: sendOperation)
    }
    let holder: PayloadHolder
//    typealias Payload = String
    typealias PayloadWithDate = (Payload, Date)

    var task: Task<(), Error>?
    
    actor PayloadHolder{
        
        init(minDelay: Duration, sendOperation: @escaping (Payload) async -> Void) {
            self.delay = minDelay
            self.sendOperation = sendOperation
        }
        
        let sendOperation: (Payload)async->()
        
        
        
        var q: PayloadWithDate? = nil
        
        var lastSent: DispatchTime? = nil
        let delay: Duration
        
        
        var delayBeforeSendingNewRequest: Duration?{
            guard let lastSent else {
                return nil
            }
//            if verbose{
    //            print("lastScehduled at: "+timeStringWithMillies(date: lastScheduledAt, withNanoOffset: nanoOffset.uptimeNanoseconds))
//            }
            
    //        precondition
            guard lastSent < .now() else{
                fatalError()
            }
    //        how long ago was the last request sent?
            let distanceToNow = lastSent.distance(to: .now())
            let durationToNow:Duration = .dispatchTimeInterval(distanceToNow)
            
            let delayOffsetDuration: Duration = delay - durationToNow
            
            let lastScheduleAffectsUs = delayOffsetDuration > .zero
            
            return lastScheduleAffectsUs ? delayOffsetDuration : nil
            
        }
        func sendNoDelay()async{
            let p = q!.0
            await sendOperation(p)
//            print("Sent \(p)")
            self.q = nil
            return
        }
        func replaceIfNewer(with t: PayloadWithDate){
            guard let current = self.q else {
                self.q = t
//                print("Replaced [none] with \(t.0)")
                return
            }
//            replace, if it's older than what I have planned
            if current.1 < t.1{
//                print("Will replace \(current.0) with \(t.0) because it's newer than what's planned.")
                self.q = t
//                print("Replaced \(current.0) with \(t.0)")
            }else{
//                print("Ignored \(t.0) because it's older than what's planned.")
            }
        }
    }
    var planned = false
    func plan(_ p: Payload) async{
        guard !planned else{
//            print("[\(p)] already planned")
            return
        }
//        print("[\(p)] planning")
        self.planned = true
        guard let delayBeforeSendingNewRequest = await holder.delayBeforeSendingNewRequest else {
            await holder.sendNoDelay()
//            print("[\(p)] planning ended")
            return
        }
        try! await Task.sleep(for: delayBeforeSendingNewRequest)
        await holder.sendNoDelay()
        self.planned = false
//        print("[\(p)] planning ended")
    }
    func add(_ t: PayloadWithDate)async{
        await holder.replaceIfNewer(with: t)
        await plan(t.0)
    }
    
}

public struct RateLimitterWithUpdating<Payload>{
    public init(sendOp: @escaping (Payload)async->()) {
        self.rl = .init(sendOperation: sendOp)
    }
    let rl: _RL<Payload>
    public func add(_ s: Payload, _ d: Date)async{
        await self.rl.add((s, d))
    }
}
