//
//  TakeTwo.swift
//  
//
//  Created by Andreas Loizides on 24/06/2024.
//

import Dispatch
import Foundation

actor _RL{
    init(sendOperation: @escaping (Payload) -> Void) {
        self.sendOperation = sendOperation
    }
    
    typealias Payload = String
    typealias PayloadWithDate = (Payload, Date)
    let sendOperation: (Payload)async->()
    var q: PayloadWithDate? = nil
    var lastSent: DispatchTime? = nil
    let delay: Duration = .milliseconds(650)
    let verbose = true
    
    private var delayBeforeSendingNewRequest: Duration?{
        guard let lastSent else {
            return nil
        }
        if verbose{
//            print("lastScehduled at: "+timeStringWithMillies(date: lastScheduledAt, withNanoOffset: nanoOffset.uptimeNanoseconds))
        }
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
    
    
    private func send()async{
        guard let q else {fatalError()}
        print("would send \(q.0) w date \(q.1)")
        await sendOperation(q.0)
    }
    
    private func trigger()async{
        guard let lastSent else{
//            send immediately
            await send()
            return
        }
//        wait
        
    }
//    Add a payload to send. If one is already scheduled, replace it, iff this is newer.
//
    var task: Task<(), Error>?
    func add(_ t: PayloadWithDate){
        guard let task else{
            return
        }
        guard let d = delayBeforeSendingNewRequest else{
            return
        }
        self.task = Task{
            try await Task.sleep(for: d)
            await send()
        }
    }
}

struct RL{
    let rl: _RL
}
