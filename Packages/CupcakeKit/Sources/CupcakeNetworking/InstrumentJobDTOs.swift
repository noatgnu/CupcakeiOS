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
    public let staff: [Int64]
    public let staffUsernames: [String]
}

/// `PATCH instrument-jobs/{id}/` body for lab group assignment — writable at the serializer
/// level (`ccm/serializers.py`), just not part of the initial create call.
public struct UpdateInstrumentJobLabGroupRequest: Encodable, Sendable {
    public var labGroup: Int64

    public init(labGroup: Int64) {
        self.labGroup = labGroup
    }
}

/// `PATCH instrument-jobs/{id}/` body for assigning the booked instrument. Required for the
/// server-side metadata-merge signal (`ccm/signals.py:175-260`) to do anything at all —
/// confirmed live: `merge_instrument_metadata_on_booking` bails immediately if
/// `instrument_job.instrument` is unset (`if not instrument_job.instrument: return`), which it
/// always was before this existed, since nothing in the booking sequence set it. The 3-call
/// booking sequence (usage → annotation → link) all succeeded without error regardless, making
/// this a genuinely silent failure — the whole booking→merge feature did nothing in real usage
/// until this was added.
public struct UpdateInstrumentJobInstrumentRequest: Encodable, Sendable {
    public var instrument: Int64

    public init(instrument: Int64) {
        self.instrument = instrument
    }
}

/// `PATCH instrument-jobs/{id}/` body for staff assignment. Server-side validation
/// (`InstrumentJobSerializer.validate`, `ccm/serializers.py:356-409`) rejects this with a 400 and
/// a specific message unless every listed user is (a) a *direct* member of the job's already-set
/// `lab_group` and (b) has `can_process_jobs=True` for that lab group — confirmed live, not
/// assumed from reading the validator alone. Both conditions can fail independently with
/// different messages naming the offending usernames; callers should surface `APIError.http`'s
/// body rather than a generic "couldn't sync" for this call specifically.
public struct UpdateInstrumentJobStaffRequest: Encodable, Sendable {
    public var staff: [Int64]

    public init(staff: [Int64]) {
        self.staff = staff
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

public struct ProjectColumnValuesResponse: Decodable, Sendable {
    public let values: [String]
}
