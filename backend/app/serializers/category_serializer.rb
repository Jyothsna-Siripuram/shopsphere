class CategorySerializer
  def self.call(category)
    {
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      parent_id: category.parent_id,
      position: category.position
    }
  end
end
