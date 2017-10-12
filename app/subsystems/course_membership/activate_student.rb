module CourseMembership
  class ActivateStudent
    lev_routine express_output: :student

    def exec(student:)
      fatal_error(code: :already_active,
                  message: 'Student is already active') unless student.dropped?
      fatal_error(code: :student_identifier_has_already_been_taken,
                  message: 'Student identifier has already been taken') \
        if student.student_identifier.present? &&
           CourseMembership::Models::Student.exists?(student_identifier: student.student_identifier)
      student.restore
      student.clear_association_cache
      transfer_errors_from(student, { type: :verbatim }, true)

      OpenStax::Biglearn::Api.update_rosters(course: student.course)

      ReassignPublishedPeriodTaskPlans[period: student.period]
      outputs[:student] = student
    end
  end
end
