class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Convention: dependent deletion is owned by the database.
  #
  # Every foreign key in this schema declares an explicit ON DELETE behaviour
  # (see docs/DATABASE.md section 7). Associations therefore do NOT declare
  # `dependent:`, because doing so would make Rails delete children row by row
  # before the parent, so the constraint never fires and the guarantee moves
  # back into application code.
  #
  # The exception is an association whose children own external state, such as
  # a file in S3, which the database cannot clean up. Those declare
  # `dependent: :destroy` explicitly and say why.
end
