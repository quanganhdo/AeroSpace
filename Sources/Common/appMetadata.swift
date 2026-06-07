public let stableAeroSpaceAppId: String = "do.anh.Aerospace"
#if DEBUG
    public let aeroSpaceAppId: String = "do.anh.Aerospace.debug"
    public let aeroSpaceAppName: String = "AeroSpace-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "AeroSpace"
#endif
