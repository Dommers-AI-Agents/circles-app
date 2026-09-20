import Foundation

extension NotificationCenter {
    /// Posts on the main thread, from wherever you are.
    ///
    /// `NotificationCenter.post` is synchronous: it runs every observer on the
    /// calling thread. `APIService.request` hands its completion back on
    /// URLSession's background queue, so a service that posted straight from a
    /// completion ran its observers — view controllers, labels, layout
    /// constraints — off the main thread. Mutating the layout engine there is
    /// an uncaught `NSInternalInconsistencyException`, not a warning: checking
    /// in while that place's page was open crashed the app outright.
    ///
    /// Services post through this instead. Already on main, it posts inline so
    /// observers still see the notification before the caller continues.
    func postOnMain(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        let post = { self.post(name: name, object: object, userInfo: userInfo) }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
