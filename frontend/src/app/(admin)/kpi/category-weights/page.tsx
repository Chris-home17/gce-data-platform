import type { Metadata } from 'next'
import { CategoryWeightsView } from './category-weights-view'

export const metadata: Metadata = { title: 'KPI Category Weights' }

export default function KpiCategoryWeightsPage() {
  return <CategoryWeightsView />
}
