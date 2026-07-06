/// Field names/types verified directly against `ccm/models.py:960-1097` (`InstrumentJob`) and
/// `ccm/serializers.py:196-334` (`InstrumentJobSerializer`) — an independent subsystem from
/// `ccrv`'s Session/Protocol/StepReagent/InstrumentUsage (no FK relationship exists between
/// them; the only cross-app link is `project`). Only the fields this app's v1 Job-slice needs
/// are modeled — `sampleNumber`/`injectionVolume`/`searchEngine`/etc. exist server-side but
/// aren't surfaced yet (deferred to a later slice alongside lab group/staff assignment).
public struct InstrumentJobDTO: Decodable, Sendable {
    public let id: Int64
    public let jobName: String?
    public let jobType: String
    public let status: String
    public let project: Int64?
    public let instrument: Int64?
    public let submittedAt: String?
    public let completedAt: String?
    public let metadataTable: Int64?
    public let labGroup: Int64?
}

/// `PATCH instrument-jobs/{id}/` body for lab group assignment — writable at the serializer
/// level (`ccm/serializers.py`), just not part of the initial create call.
public struct UpdateInstrumentJobLabGroupRequest: Encodable, Sendable {
    public var labGroup: Int64

    public init(labGroup: Int64) {
        self.labGroup = labGroup
    }
}

/// `POST instrument-jobs/` body. Matches the reference web app's own minimal create payload
/// (`job-submission.ts` step 1) exactly — every other field (lab group, staff, samples,
/// template) is a separate `PATCH` keyed off the already-created draft job id, not part of one
/// combined create call. `user` is writable at the serializer level but force-overwritten
/// server-side from the requesting user (`InstrumentJobViewSet.perform_create`,
/// `ccm/viewsets.py:415-417`), so it's not included here.
public struct CreateInstrumentJobRequest: Encodable, Sendable {
    public var jobType: String
    public var jobName: String?
    public var project: Int64?

    public init(jobType: String = "analysis", jobName: String?, project: Int64?) {
        self.jobType = jobType
        self.jobName = jobName
        self.project = project
    }
}
