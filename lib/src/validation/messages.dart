/// Default English messages (Laravel's `lang/en/validation.php`, Phase 1 subset).
/// Size rules map `numeric|string|array` to a variant.
const Map<String, Object> defaultMessages = {
  'accepted': 'The :attribute field must be accepted.',
  'after': 'The :attribute field must be a date after :date.',
  'alpha': 'The :attribute field must only contain letters.',
  'alpha_dash':
      'The :attribute field must only contain letters, numbers, dashes, and underscores.',
  'alpha_num': 'The :attribute field must only contain letters and numbers.',
  'array': 'The :attribute field must be an array.',
  'before': 'The :attribute field must be a date before :date.',
  'between': {
    'numeric': 'The :attribute field must be between :min and :max.',
    'string': 'The :attribute field must be between :min and :max characters.',
    'array': 'The :attribute field must have between :min and :max items.',
  },
  'boolean': 'The :attribute field must be true or false.',
  'confirmed': 'The :attribute field confirmation does not match.',
  'date': 'The :attribute field must be a valid date.',
  'different': 'The :attribute field and :other must be different.',
  'digits': 'The :attribute field must be :digits digits.',
  'digits_between':
      'The :attribute field must be between :min and :max digits.',
  'email': 'The :attribute field must be a valid email address.',
  'ends_with':
      'The :attribute field must end with one of the following: :values.',
  'in': 'The selected :attribute is invalid.',
  'integer': 'The :attribute field must be an integer.',
  'max': {
    'numeric': 'The :attribute field must not be greater than :max.',
    'string': 'The :attribute field must not be greater than :max characters.',
    'array': 'The :attribute field must not have more than :max items.',
  },
  'min': {
    'numeric': 'The :attribute field must be at least :min.',
    'string': 'The :attribute field must be at least :min characters.',
    'array': 'The :attribute field must have at least :min items.',
  },
  'not_in': 'The selected :attribute is invalid.',
  'not_regex': 'The :attribute field format is invalid.',
  'numeric': 'The :attribute field must be a number.',
  'present': 'The :attribute field must be present.',
  'regex': 'The :attribute field format is invalid.',
  'required': 'The :attribute field is required.',
  'required_if': 'The :attribute field is required when :other is :value.',
  'required_unless':
      'The :attribute field is required unless :other is in :values.',
  'required_with': 'The :attribute field is required when :values is present.',
  'required_without':
      'The :attribute field is required when :values is not present.',
  'same': 'The :attribute field must match :other.',
  'size': {
    'numeric': 'The :attribute field must be :size.',
    'string': 'The :attribute field must be :size characters.',
    'array': 'The :attribute field must contain :size items.',
  },
  'starts_with':
      'The :attribute field must start with one of the following: :values.',
  'string': 'The :attribute field must be a string.',
  'url': 'The :attribute field must be a valid URL.',
  'uuid': 'The :attribute field must be a valid UUID.',
};
