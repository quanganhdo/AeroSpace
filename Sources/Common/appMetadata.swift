public let stableAeroSpaceSocketId: String = "bobko.aerospace"
#if DEBUG
    public let aeroSpaceAppId: String = "do.anh.Aerospace.debug"
    public let aeroSpaceSocketId: String = "bobko.aerospace.debug"
    public let aeroSpaceAppName: String = "AeroSpace-Debug"
#else
    public let aeroSpaceAppId: String = "do.anh.Aerospace"
    public let aeroSpaceSocketId: String = stableAeroSpaceSocketId
    public let aeroSpaceAppName: String = "AeroSpace"
#endif
