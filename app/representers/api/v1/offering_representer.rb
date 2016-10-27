class Api::V1::OfferingRepresenter < Roar::Decorator

  include Roar::JSON
  include Representable::Coercion

  property :id,
           type: String,
           readable: true,
           writeable: false,
           schema_info: { required: true }

  property :is_concept_coach,
           readable: true,
           writeable: false,
           schema_info: {
             required: true,
             type: 'boolean'
           }

  property :appearance_code,
           type: String,
           readable: true,
           writeable: false,
           schema_info: { required: true }

  collection :active_term_years,
             class: TermYear,
             extend: Api::V1::TermYearRepresenter,
             readable: true,
             writeable: false,
             getter: ->(*) { TermYear.visible_term_years },
             schema_info: { required: true }

end
